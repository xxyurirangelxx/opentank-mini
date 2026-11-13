import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import '../core/protocol/messages.dart' show Command, isValidResponse, maxRead;
import '../core/transport/transport.dart';

/// Transporte BLE pelo serviço proprietario da M-VAVE.
///
/// Servico `0000ae40-...`, escrita em `ae41` (sem resposta), notificacao em
/// `ae42`. Neste transporte o payload trafega **cru**, sem `F0`/`F7` e sem
/// empacotamento de 7 bits. A camada de cima continua falando SysEx, entao esse
/// transporte converte nas duas direcoes.
class BleTransport implements TankTransport, BleDisconnectHook {
  BleTransport({required this.deviceName});

  static const String serviceUuid = '0000ae40-0000-1000-8000-00805f9b34fb';
  static const String txUuid = '0000ae41-0000-1000-8000-00805f9b34fb';
  static const String rxUuid = '0000ae42-0000-1000-8000-00805f9b34fb';

  /// Nome anunciado pela pedal.
  final String deviceName;

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final BytesBuilder _assembly = BytesBuilder(copy: true);
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<bool>? _connectionSubscription;
  String? _deviceId;
  int _chunkSize = 20;
  int? _expectedResponseLength;

  /// Assinatura para quando o sistema derrubar o link.
  @override
  void Function()? onDisconnected;

  /// Tamanho de fragmento negociado.
  ///
  /// O valor padrao do BLE e 23 bytes de MTU, dos quais 3 sao cabecalho ATT.
  /// Pedir MTU maior reduz muito o tempo de uma leitura de 92 bytes (de 5
  /// escritas para 1) e e o principal alivio para a instabilidade do Bluetooth.
  int get chunkSize => _chunkSize;

  @override
  String get name => deviceName;

  /// Procura dispositivos cujo nome combina com [deviceName].
  static Future<List<BleDevice>> scan({
    required String deviceName,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final found = <String, BleDevice>{};
    final subscription = UniversalBle.scanStream.listen((BleDevice device) {
      final label = device.name ?? device.rawName ?? '';
      if (label.toLowerCase().contains(deviceName.toLowerCase()) &&
          device.connectable != false) {
        found[device.deviceId] = device;
      }
    });
    await UniversalBle.startScan();
    await Future<void>.delayed(timeout);
    await UniversalBle.stopScan();
    await subscription.cancel();
    return found.values.toList();
  }

  @override
  Future<void> open() async {
    final device = await scan(deviceName: deviceName);
    if (device.isEmpty) {
      throw TransportException('Dispositivo BLE "$deviceName" nao encontrado');
    }
    if (device.length > 1) {
      throw TransportException(
        'Mais de um dispositivo BLE corresponde a "$deviceName"',
      );
    }
    _deviceId = device.single.deviceId;
    final deviceId = _deviceId!;
    await UniversalBle.connect(deviceId, timeout: const Duration(seconds: 20));
    // Depois de conectar, o sistema ainda pode derrubar o link. Escutar aqui e
    // o que permite avisar a interface em vez de deixar a proxima requisicao
    // morrer no timeout.
    _connectionSubscription = UniversalBle.connectionStream(deviceId)
        .listen((bool connected) {
          if (!connected) onDisconnected?.call();
        });

    final services = await UniversalBle.discoverServices(deviceId);
    final hasService = services.any(
      (BleService s) => _normalize(s.uuid).contains('ae40'),
    );
    if (!hasService) {
      await _teardown(deviceId);
      throw TransportException('Servico AE40 ausente; aparelho inesperado');
    }

    // Pedir MTU maior e best effort: se o pedal recusar, seguimos com 23 bytes.
    try {
      final mtu = await UniversalBle.requestMtu(
        deviceId,
        185,
        timeout: const Duration(seconds: 5),
      );
      _chunkSize = mtu > 3 ? mtu - 3 : 20;
    } catch (_) {
      _chunkSize = 20;
    }

    await UniversalBle.subscribeNotifications(deviceId, serviceUuid, rxUuid);
    _subscription = UniversalBle.characteristicValueStream(
      deviceId,
      rxUuid,
    ).listen(_onNotification);
  }

  /// Fecha o link atual e esquece o dispositivo.
  Future<void> _teardown(String deviceId) async {
    await _subscription?.cancel();
    _subscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {
      // Pode ja estar desconectado.
    }
    _deviceId = null;
  }

  @override
  Future<void> send(List<int> raw) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw TransportException('Transporte BLE nao aberto');
    }
    // Uma resposta parcial da tentativa anterior nao pertence ao novo pedido.
    _assembly.clear();
    // A identificacao tem tamanho variavel; os demais comandos retornam ACK
    // ou uma resposta de leitura cujo tamanho ja e conhecido pelo pedido.
    _expectedResponseLength = raw.length < 3 || raw[2] == Command.identify
        ? null
        : raw[2] == Command.read && raw.length >= 13
        ? (raw[11] | (raw[12] << 8)) + 15
        : 8;
    // Aqui a mensagem trafega crua: sem F0/F7 e sem empacotamento de 7 bits.
    for (var offset = 0; offset < raw.length; offset += _chunkSize) {
      final end = offset + _chunkSize;
      final chunk = Uint8List.fromList(
        raw.sublist(offset, end > raw.length ? raw.length : end),
      );
      await UniversalBle.write(
        deviceId,
        serviceUuid,
        txUuid,
        chunk,
        withoutResponse: true,
      );
      // O pedal precisa de folga entre fragmentos. Com MTU negociado o quadro
      // costuma caber inteiro, entao na pratica isto quase nunca atrasa.
      if (end < raw.length) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    }
  }

  void _onNotification(Uint8List data) {
    _assembly.add(data);
    var buffered = _assembly.takeBytes();
    while (buffered.isNotEmpty) {
      // Fragmentos tardios podem preceder o cabecalho da nova resposta.
      if (buffered[0] != 0x00 || (buffered.length > 1 && buffered[1] != 0x59)) {
        buffered = buffered.sublist(1);
        continue;
      }
      if (buffered.length < 5) break;
      final total = (buffered[3] | (buffered[4] << 8)) + 7;
      final expected = _expectedResponseLength;
      if (total < 8 ||
          total > maxRead + 15 ||
          (expected != null && total != 8 && total != expected)) {
        buffered = buffered.sublist(1);
        continue;
      }
      if (buffered.length < total) break;
      final frame = buffered.sublist(0, total);
      if (!isValidResponse(frame)) {
        buffered = buffered.sublist(1);
        continue;
      }
      _incoming.add(frame);
      buffered = buffered.sublist(total);
    }
    _assembly.add(buffered);
  }

  static String _normalize(String uuid) =>
      uuid.toLowerCase().replaceAll('-', '');

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    onDisconnected = null;
    final deviceId = _deviceId;
    if (deviceId != null) {
      try {
        await UniversalBle.unsubscribe(deviceId, serviceUuid, rxUuid);
      } catch (_) {
        // Silencioso: o dispositivo pode ja ter desconectado.
      }
      await _teardown(deviceId);
    }
    _deviceId = null;
    await _incoming.close();
  }
}

import 'dart:async';

import '../model/model_flash.dart';
import '../model/preset.dart';
import '../protocol/messages.dart';
import '../transport/transport.dart';

/// Erro de leitura.
class ReadException implements Exception {
  ReadException(this.message);

  final String message;

  @override
  String toString() => 'ReadException: $message';
}

/// Erro de escrita.
class WriteException implements Exception {
  WriteException(this.message);

  final String message;

  @override
  String toString() => 'WriteException: $message';
}

/// A gravacao foi aceita mas a releitura nao confere.
class FlashWriteException extends WriteException {
  FlashWriteException(super.message);
}

/// Uma resposta recebida do dispositivo.
class _Response {
  bool accepts(List<int> raw) => true;

  /// `00 59 00 01 00 00 00 FF` — aceito.
  ///
  /// O byte 3 vale `01` tanto no ACK quanto no NAK; o que distingue e o byte 6
  /// (`00` aceito, `01` recusado).
  static bool isAck(List<int> raw) =>
      raw.length >= 8 &&
      raw[0] == 0x00 &&
      raw[1] == 0x59 &&
      raw[2] == 0x00 &&
      raw[3] == 0x01 &&
      raw[6] == 0x00;

  static bool isNak(List<int> raw) =>
      raw.length >= 8 &&
      raw[0] == 0x00 &&
      raw[1] == 0x59 &&
      raw[2] == 0x00 &&
      raw[3] == 0x01 &&
      raw[6] != 0x00;

  static bool isData(List<int> raw) =>
      raw.length >= 16 && raw[0] == 0x00 && raw[1] == 0x59 && raw[2] == 0x23;
}

/// Cliente de alto nivel da Tank Mini.
///
/// Traduz chamadas de negocio em mensagens do protocolo e valida as respostas.
/// Nao conhece Flutter nem MIDI diretamente: recebe um [TankTransport].
class TankDevice {
  TankDevice(this.transport, {this.readTimeout = const Duration(seconds: 3)});

  final TankTransport transport;
  final Duration readTimeout;

  StreamSubscription<List<int>>? _subscription;
  Completer<List<int>>? _waiter;
  String _identity = '';
  bool _open = false;

  String get identity => _identity;
  bool get isOpen => _open;

  Future<String> connect() async {
    await transport.open();
    _subscription = transport.incoming.listen(_onFrame);
    _open = true;
    _identity = await identify();
    return _identity;
  }

  Future<void> disconnect() async {
    _open = false;
    _waiter?.completeError(TransportException('Conexao encerrada'));
    _waiter = null;
    await _subscription?.cancel();
    _subscription = null;
    await transport.close();
  }

  void _onFrame(List<int> frame) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(frame);
    }
  }

  /// Envia [frame] e devolve a proxima resposta.
  ///
  /// Conversas sao estritamente sequenciais: o protocolo nao tem correlacao de
  /// ID, entao uma requisicao de cada vez.
  Future<List<int>> _exchange(List<int> frame, {Duration? timeout}) async {
    if (!_open) {
      throw StateError('Dispositivo nao conectado');
    }
    if (_waiter != null && !_waiter!.isCompleted) {
      throw StateError('Requisicao anterior ainda em andamento');
    }
    final waiter = Completer<List<int>>();
    _waiter = waiter;
    try {
      await transport.send(frame);
      return await waiter.future.timeout(timeout ?? readTimeout);
    } on TimeoutException {
      throw TimeoutException(
        'Sem resposta do dispositivo',
        timeout ?? readTimeout,
      );
    } finally {
      _waiter = null;
    }
  }

  /// Identificacao do aparelho.
  Future<String> identify() async {
    final raw = await _exchange(
      identifyRequest(),
      timeout: const Duration(seconds: 2),
    );
    final body = raw.length > 4
        ? raw.sublist(4, raw.length - 1)
        : const <int>[];
    final text = StringBuffer();
    for (final byte in body) {
      if (byte >= 0x20 && byte < 0x7F) {
        text.writeCharCode(byte);
      } else if (byte == 0x00) {
        break;
      }
    }
    final value = text.toString().trim();
    return value.isEmpty ? 'TANK MINI' : value;
  }

  // --- leitura ---

  /// Le [length] bytes de [address] numa unica requisicao (ate [maxRead]).
  Future<List<int>> readBytes(
    int address,
    int length, {
    int area = Area.presets,
    Duration? timeout,
  }) async {
    if (length <= 0 || length > maxRead) {
      throw ArgumentError('Leitura deve ter entre 1 e $maxRead bytes');
    }
    final raw = await _exchange(
      readRequest(address, length, area: area),
      timeout: timeout,
    );
    if (_Response.isNak(raw)) {
      throw ReadException('Endereco $address ilegivel');
    }
    if (!_Response.isData(raw)) {
      throw ReadException('Resposta inesperada de leitura: ${_hex(raw)}');
    }
    final payload = raw.sublist(14, raw.length - 1);
    if (payload.length != length) {
      throw ReadException(
        'Tamanho divergente: pedido $length, recebido ${payload.length}',
      );
    }
    return payload;
  }

  /// Le um bloco maior, fatiando em requisicoes de ate [maxRead] bytes.
  Future<List<int>> readBlock(
    int address,
    int length, {
    int area = Area.presets,
    Duration? timeout,
  }) async {
    final out = <int>[];
    while (out.length < length) {
      final remaining = length - out.length;
      final chunk = remaining > maxRead ? maxRead : remaining;
      out.addAll(
        await readBytes(
          address + out.length,
          chunk,
          area: area,
          timeout: timeout,
        ),
      );
    }
    return out;
  }

  /// Le o preset ativo da RAM.
  Future<Preset> readActive() async =>
      Preset.fromBytes(await readBytes(ramAddress, presetSize));

  /// Le um slot da flash.
  Future<Preset> readSlot(int slot) async =>
      Preset.fromBytes(await readBytes(slot * presetSize, presetSize));

  // --- escrita ---

  Future<void> _write(
    List<int> payload, {
    required int address,
    required int area,
    required bool commit,
  }) async {
    final raw = await _exchange(writeRequest(address, payload, area: area));
    if (_Response.isNak(raw)) {
      throw WriteException('Escrita rejeitada em $address');
    }
    if (!_Response.isAck(raw)) {
      throw WriteException('Resposta inesperada de escrita: ${_hex(raw)}');
    }
    if (commit) {
      final ack = await _exchange(commitRequest());
      if (!_Response.isAck(ack)) {
        throw WriteException('Commit nao confirmado: ${_hex(ack)}');
      }
    }
  }

  /// Grava um preset direto na flash.
  Future<void> saveSlot(int slot, Preset preset) => _write(
    preset.bytes,
    address: slot * presetSize,
    area: Area.presets,
    commit: true,
  );

  /// Seleciona o slot e, se [expected] for informado, espera a RAM convergir.
  Future<int> selectSlot(
    int slot, {
    Preset? expected,
    Duration? timeout,
  }) async {
    final raw = await _exchange(selectRequest(slot));
    if (!_Response.isAck(raw)) {
      throw WriteException('Selecao rejeitada: ${_hex(raw)}');
    }
    if (expected == null) {
      return 0;
    }
    final deadline = DateTime.now().add(timeout ?? const Duration(seconds: 3));
    var reads = 0;
    while (DateTime.now().isBefore(deadline)) {
      reads++;
      if (await readActive() == expected) {
        return reads;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    throw TimeoutException(
      'Selecao nao convergiu; o pedal pode estar em outro estado',
    );
  }

  /// Troca dois presets de slot, validando o resultado.
  Future<void> swapSlots(int a, int b) async {
    final first = await readSlot(a);
    final second = await readSlot(b);
    await saveSlot(b, first);
    await saveSlot(a, second);
    if (await readSlot(a) != second || await readSlot(b) != first) {
      throw WriteException('Swap entre $a e $b nao confirmou');
    }
  }

  // --- tempo real ---

  Future<void> setBlockEnabled(Block block, bool enabled) async {
    final raw = await _exchange(
      toggleRequest(block.toggleAddress, enabled ? 1 : 0),
    );
    if (!_Response.isAck(raw)) {
      throw WriteException('Toggle rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setBlockModel(Block block, int model) async {
    final raw = await _exchange(toggleRequest(block.modelAddress, model));
    if (!_Response.isAck(raw)) {
      throw WriteException('Troca de modelo rejeitada: ${_hex(raw)}');
    }
  }

  Future<void> setParameter(int offset, int value) async {
    final raw = await _exchange(knobRequest(offset, value));
    if (!_Response.isAck(raw)) {
      throw WriteException('Parametro rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setVolume(int value) => setParameter(0, value);

  Future<void> setRouting(List<int> order) async {
    final raw = await _exchange(routingRequest(order));
    if (!_Response.isAck(raw)) {
      throw WriteException('Routing rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setBypass(bool enabled) async {
    final raw = await _exchange(bypassRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Bypass rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setLoopback(bool enabled) async {
    final raw = await _exchange(loopbackRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Loopback rejeitado: ${_hex(raw)}');
    }
  }

  Future<void> setTuner(bool enabled) async {
    final raw = await _exchange(tunerRequest(enabled));
    if (!_Response.isAck(raw)) {
      throw WriteException('Afinador rejeitado: ${_hex(raw)}');
    }
  }

  /// Envia um buffer de modelo (AMP = 1, CAB = 2) e ativa o preview.
  Future<void> uploadModel(List<int> buffer, {required int previewKind}) async {
    for (var offset = 0; offset < buffer.length; offset += maxWrite) {
      final end = offset + maxWrite;
      final chunk = buffer.sublist(
        offset,
        end > buffer.length ? buffer.length : end,
      );
      await _write(chunk, address: offset, area: Area.model, commit: false);
    }
    final raw = await _exchange(previewModelRequest(kind: previewKind));
    if (!_Response.isAck(raw)) {
      throw WriteException('Preview de modelo rejeitado: ${_hex(raw)}');
    }
  }

  /// Grava um modelo de forma permanente na flash de modelos.
  ///
  /// O fluxo reproduz o "Restore Amp/Cab" do editor oficial: apaga os setores
  /// que o registro ocupa e escreve o registro em blocos de [maxWrite] bytes.
  /// **Nao ha commit**: a captura do editor nao envia nenhum, e enviar o
  /// commit de preset com `area 0x05` faz o pedal descartar a gravacao.
  ///
  /// Lanca [FlashWriteException] quando a releitura nao bate com o envio.
  Future<void> writeModelFlash(
    int address,
    List<int> record, {
    void Function(double progress)? onProgress,
  }) async {
    final sectors = eraseSectorsFor(address, record.length);
    final blocks = (record.length / maxWrite).ceil();
    final total = sectors.length + blocks + 1;
    var done = 0;

    for (final sector in sectors) {
      final raw = await _exchange(eraseSectorRequest(sector));
      if (!_Response.isAck(raw)) {
        throw WriteException('Apagamento de ${_hex32(sector)} recusado');
      }
      onProgress?.call(++done / total);
    }

    for (var offset = 0; offset < record.length; offset += maxWrite) {
      final end = offset + maxWrite;
      final chunk = record.sublist(
        offset,
        end > record.length ? record.length : end,
      );
      await _write(
        chunk,
        address: address + offset,
        area: Area.model,
        commit: false,
      );
      onProgress?.call(++done / total);
    }

    final check = await readBlock(address, record.length, area: Area.model);
    for (var i = 0; i < record.length; i++) {
      if (check[i] != record[i]) {
        throw FlashWriteException(
          'Verificacao falhou em ${_hex32(address + i)}: '
          'gravado ${check[i].toRadixString(16)}, '
          'esperado ${record[i].toRadixString(16)}',
        );
      }
    }
    onProgress?.call(1);
  }

  /// Le o registro de um modelo da flash (8192 para AMP, 4096 para CAB).
  Future<List<int>> readModelFlash(int address, int length) =>
      readBlock(address, length, area: Area.model);

  static String _hex32(int value) =>
      '0x${value.toRadixString(16).padLeft(8, '0')}';

  static String _hex(List<int> data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/device/tank_device.dart';
import '../core/model/model_flash.dart';
import '../core/model/model_format.dart';
import '../core/model/preset.dart';
import '../core/model/preset_bank.dart';
import '../core/protocol/messages.dart';
import '../core/transport/transport.dart';
import '../platform/ble_transport.dart';
import '../platform/midi_transport.dart';

/// Estado da conexao com a pedal.
enum TankConnectionState { idle, scanning, connecting, connected, error }

/// Como o app fala com a pedal.
enum Link { usb, bluetooth }

/// Cria o transporte adequado a plataforma e ao tipo de link.
///
/// Android nao tem MIDI nativo no plugin, entao USB so aparece onde ha suporte.
TankTransport createTransport(
  Link link, {
  String midiName = 'USB-Midi',
  String bleName = 'TANK MINI_BLE',
}) {
  switch (link) {
    case Link.usb:
      return MidiTransport(deviceName: midiName);
    case Link.bluetooth:
      return BleTransport(deviceName: bleName);
  }
}

/// Controlador principal do aplicativo.
///
/// Mantem o dispositivo, o banco de presets e o rascunho em edicao. A regra
/// central: alteracoes na interface vao para o rascunho e sao aplicadas ao
/// pedal em tempo real (RAM), mas **nao** sao gravadas na flash ate o usuario
/// pedir Save.
class TankController extends ChangeNotifier {
  TankController({
    this.deviceName = 'USB-Midi',
    this.bleName = 'TANK MINI_BLE',
    Link initialLink = Link.usb,
    TankTransport Function(Link link)? transportFactory,
  }) : _link = initialLink {
    _transportFactory = transportFactory;
  }

  final String deviceName;
  final String bleName;
  late final TankTransport Function(Link link)? _transportFactory;
  Link _link;

  /// Link escolhido pelo usuario.
  Link get link => _link;

  /// Existe suporte a USB nesta plataforma?
  static bool get supportsUsb =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  TankDevice? _device;
  TankConnectionState _state = TankConnectionState.idle;
  String _message = '';
  PresetBank? _bank;
  Preset? _draft;
  int _activeSlot = 0;
  bool _busy = false;

  /// Nomes de AMP e CAB lidos do pedal. Vazio enquanto desconectado.
  ModelNames _modelNames = ModelNames.empty;

  TankConnectionState get state => _state;
  String get statusMessage => _message;
  PresetBank? get bank => _bank;
  Preset? get draft => _draft;
  int get activeSlot => _activeSlot;
  bool get busy => _busy;
  bool get connected => _state == TankConnectionState.connected;
  TankDevice? get device => _device;

  /// Nomes dos modelos como o pedal os reporta.
  ModelNames get modelNames => _modelNames;

  /// Nomes de modelo de um bloco, na ordem do indice do preset.
  ///
  /// So AMP e CAB tem tabela no pedal; os demais voltam vazios e a interface
  /// mostra o numero do modelo.
  List<String> modelNamesFor(Block block) {
    switch (block) {
      case Block.amp:
        return _modelNames.amp;
      case Block.cab:
        return _modelNames.cab;
      case Block.fx:
      case Block.mod:
      case Block.dly:
      case Block.rev:
        return const <String>[];
    }
  }

  Preset? _pending;
  bool _draining = false;

  /// Envia o estado pendente mais recente, um por vez.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending != null) {
        final device = _device;
        final target = _pending!;
        final current = _draft;
        _pending = null;
        if (device == null || current == null) continue;
        final baseline = _lastSent ?? current;
        try {
          await _push(baseline, target);
          _lastSent = target;
        } catch (error) {
          _message = 'Alteração rejeitada: $error';
          _pending = null;
          notifyListeners();
          break;
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Ultimo estado confirmado no pedal; base das diferencas enviadas.
  Preset? _lastSent;

  /// Consulta periodica do preset ativo.
  ///
  /// O pedal **nao avisa** quando o usuario mexe nele: escutando a porta por 20
  /// segundos sem enviar nada chegam zero mensagens. O editor oficial resolve
  /// consultando o estado a cada 1 segundo (medido nas capturas: 360 envios da
  /// mesma leitura, intervalo mediano de 1,000 s). E o mesmo caminho aqui.
  Timer? _pollTimer;
  bool _polling = false;

  /// Intervalo entre consultas. Um segundo e o que o editor oficial usa e o
  /// pedal responde bem; mais rapido so gasta radio no Bluetooth.
  static const Duration pollInterval = Duration(seconds: 1);

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Le o preset ativo e adota o que mudou no pedal.
  ///
  /// Nao roda enquanto ha envio em andamento: a resposta poderia chegar antes
  /// de o pedal aplicar a edicao e a interface voltaria um passo.
  Future<void> _poll() async {
    final device = _device;
    if (device == null || !connected || _polling) return;
    if (_busy || _draining || _pending != null) return;
    _polling = true;
    try {
      final active = await device.readActive();
      final known = _lastSent;
      if (known != null && active == known) return;
      _adopt(active);
    } catch (error) {
      // Uma consulta perdida nao derruba a sessao; a proxima tenta de novo.
      debugPrint('consulta periodica falhou: $error');
    } finally {
      _polling = false;
    }
  }

  /// Adota um estado que veio do pedal.
  void _adopt(Preset active) {
    final bank = _bank;
    _draft = active;
    _lastSent = active;
    if (bank != null) {
      final match = _matchingSlot(bank.slots, active);
      if (match >= 0) _activeSlot = match;
    }
    notifyListeners();
  }

  /// Rascunho difere do que esta salvo no slot?
  bool get isDirty {
    final bank = _bank;
    final draft = _draft;
    if (bank == null || draft == null) return false;
    return bank.slots[_activeSlot] != draft;
  }

  /// Carrega um banco e um rascunho sem falar com o pedal.
  ///
  /// Existe para testes de interface e para abrir o editor em modo offline,
  /// quando o usuario quiser so inspecionar um arquivo.
  @visibleForTesting
  void loadOffline(PresetBank bank, {int activeSlot = 0, Preset? draft}) {
    _bank = bank;
    _activeSlot = activeSlot;
    _draft = draft ?? bank.slots[activeSlot];
    _state = TankConnectionState.connected;
    _message = 'Offline';
    notifyListeners();
  }

  /// Troca o link (USB ou Bluetooth). Precisa estar desconectado.
  void setLink(Link link) {
    if (connected || _state == TankConnectionState.connecting) return;
    _link = link;
    _message = '';
    notifyListeners();
  }

  Future<void> connect() async {
    if (_state == TankConnectionState.connecting || connected) return;
    _state = TankConnectionState.connecting;
    _message = 'Procurando a pedal...';
    notifyListeners();
    final transport =
        _transportFactory?.call(_link) ??
        createTransport(_link, midiName: deviceName, bleName: bleName);
    final device = TankDevice(transport);
    try {
      final identity = await device.connect();
      _device = device;
      _state = TankConnectionState.connected;
      _message = identity;
      notifyListeners();
      // Se o transporte cair (BLE desconectado pelo sistema, cabo removido), a
      // sessao termina de forma limpa em vez de falhar em toda requisicao.
      _lostSubscription = device.lost.listen((_) => _onLinkLost());
      await refresh();
    } catch (error) {
      _state = TankConnectionState.error;
      _message = 'Falha ao conectar: $error';
      notifyListeners();
      try {
        await device.disconnect();
      } catch (_) {
        // O transporte pode nem ter aberto.
      }
    }
  }

  StreamSubscription<void>? _lostSubscription;

  /// O link caiu por conta do sistema.
  ///
  /// Mantem o banco lido e o rascunho na tela, mas marca como desconectado: o
  /// usuario ve o estado real e pode reconectar sem perder o que estava vendo.
  void _onLinkLost() {
    _stopPolling();
    _pollTimer = null;
    if (_state != TankConnectionState.connected) return;
    _state = TankConnectionState.error;
    _message = 'Conexão perdida';
    notifyListeners();
  }

  Future<void> disconnect() async {
    final device = _device;
    _stopPolling();
    await _lostSubscription?.cancel();
    _lostSubscription = null;
    _device = null;
    _state = TankConnectionState.idle;
    _message = '';
    _bank = null;
    _draft = null;
    _lastSent = null;
    _pending = null;
    _modelNames = ModelNames.empty;
    notifyListeners();
    await device?.disconnect();
  }

  /// Le os 21 slots e o preset ativo.
  Future<void> refresh() async {
    final device = _device;
    if (device == null) return;
    await _guard(() async {
      final slots = <Preset>[];
      for (var i = 0; i < 21; i++) {
        slots.add(await device.readSlot(i));
      }
      final active = await device.readActive();
      _bank = PresetBank(slots);
      _activeSlot = _matchingSlot(slots, active);
      _draft = active;
      _lastSent = active;
      _message = device.identity;
      _modelNames = await _readNames(device);
      _startPolling();
    });
  }

  /// Le os nomes sem derrubar a conexao se a tabela nao responder.
  ///
  /// Um pedal com firmware diferente pode nao expor as tabelas; nesse caso a
  /// interface volta a mostrar o numero do modelo, mas o editor continua
  /// utilizavel.
  Future<ModelNames> _readNames(TankDevice device) async {
    try {
      return await device.readModelNames();
    } catch (error) {
      debugPrint('nomes de modelo indisponiveis: $error');
      return ModelNames.empty;
    }
  }

  int _matchingSlot(List<Preset> slots, Preset active) {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] == active) return i;
    }
    // Estado nao salvo: mantem o slot selecionado.
    return _activeSlot;
  }

  /// Slot cujo conteudo salvo corresponde ao preset ativo, ou `null` quando o
  /// pedal esta com uma edicao nao salva.
  ///
  /// A interface usa isto para nao mentir no seletor de slot: antes, qualquer
  /// estado nao reconhecido fazia o seletor cair no slot anterior.
  int? get matchedSlot {
    final bank = _bank;
    final draft = _draft;
    if (bank == null || draft == null) return null;
    for (var i = 0; i < bank.slots.length; i++) {
      if (bank.slots[i] == draft) return i;
    }
    return null;
  }

  /// Seleciona um slot no pedal.
  Future<void> selectSlot(int index) async {
    final device = _device;
    final bank = _bank;
    if (device == null || bank == null) return;
    await _guard(() async {
      _activeSlot = index;
      _draft = await device.readActive();
      await device.selectSlot(index, expected: bank.slots[index]);
      _draft = await device.readActive();
      _lastSent = _draft;
    });
  }

  /// Aplica uma alteracao ao rascunho e ao pedal.
  Future<void> apply(Preset next) async {
    final device = _device;
    final previous = _draft;
    if (previous == null) return;
    if (device != null) {
      // Arrastar um slider dispara dezenas de eventos por segundo e o
      // protocolo so aceita uma conversa por vez. Guarda apenas o estado mais
      // recente e deixa um unico envio em andamento.
      _pending = next;
      _draft = next;
      notifyListeners();
      await _drain();
      return;
    }
    // Sem pedal (modo offline) a edicao fica so no rascunho.
    if (device == null) {
      _draft = next;
      notifyListeners();
      return;
    }
    _draft = next;
    notifyListeners();
    try {
      await _push(previous, next);
    } catch (error) {
      _draft = previous;
      _message = 'Alteração rejeitada: $error';
      notifyListeners();
    }
  }

  Future<void> _push(Preset from, Preset to) async {
    final device = _device!;
    if (from.volume != to.volume) {
      await device.setVolume(to.volume);
    }
    if (from.routing.join(',') != to.routing.join(',')) {
      await device.setRouting(to.routing);
    }
    for (final block in Block.values) {
      if (from.isEnabled(block) != to.isEnabled(block)) {
        await device.setBlockEnabled(block, to.isEnabled(block));
      }
      if (from.model(block) != to.model(block)) {
        await device.setBlockModel(block, to.model(block));
      }
      for (final offset in Preset.parameterOffsets[block]!) {
        if (from.parameter(offset) != to.parameter(offset)) {
          await device.setParameter(offset, to.parameter(offset));
        }
      }
    }
  }

  /// Grava o rascunho no slot ativo.
  Future<void> save() async {
    final device = _device;
    final draft = _draft;
    if (device == null || draft == null) return;
    await _guard(() async {
      await device.saveSlot(_activeSlot, draft);
      await device.selectSlot(_activeSlot, expected: draft);
      _bank = _bank!.withSlot(_activeSlot, draft);
      _message = 'Preset salvo';
    });
  }

  /// Grava o rascunho em outro slot.
  Future<void> saveTo(int index) async {
    final device = _device;
    final draft = _draft;
    if (device == null || draft == null) return;
    await _guard(() async {
      await device.saveSlot(index, draft);
      _bank = _bank!.withSlot(index, draft);
      _message = 'Preset copiado para ${slotLabel(index)}';
    });
  }

  /// Troca dois slots.
  Future<void> swap(int a, int b) async {
    final device = _device;
    final bank = _bank;
    if (device == null || bank == null) return;
    await _guard(() async {
      await device.swapSlots(a, b);
      final slots = List<Preset>.of(bank.slots);
      final temp = slots[a];
      slots[a] = slots[b];
      slots[b] = temp;
      _bank = PresetBank(slots);
      _message = '${slotLabel(a)} <-> ${slotLabel(b)}';
    });
  }

  /// Desfaz as alteracoes nao salvas.
  ///
  /// Aplica o conteudo salvo no slot de volta ao pedal (RAM) e adota esse
  /// conteudo como rascunho. Ler a RAM nao serviria: a RAM tem justamente a
  /// edicao que se quer descartar.
  Future<void> revert() async {
    final device = _device;
    final bank = _bank;
    if (device == null || bank == null) return;
    await _guard(() async {
      final saved = bank.slots[_activeSlot];
      // Reescreve a RAM com os valores salvos, campo a campo.
      await _push(_draft ?? saved, saved);
      _draft = await device.readActive();
      _lastSent = _draft;
    });
  }

  /// Grava um banco completo nos 21 slots e confere por releitura.
  Future<void> restoreBank(PresetBank bank) async {
    final device = _device;
    if (device == null) {
      throw StateError('Dispositivo nao conectado');
    }
    _busy = true;
    notifyListeners();
    try {
      for (var slot = 0; slot < PresetBank.slotCount; slot++) {
        await device.saveSlot(slot, bank.slots[slot]);
      }
      for (var slot = 0; slot < PresetBank.slotCount; slot++) {
        final actual = await device.readSlot(slot);
        if (actual != bank.slots[slot]) {
          throw StateError(
            'Slot ${slotLabel(slot)} nao confere apos a gravacao',
          );
        }
      }
      _bank = bank;
      _activeSlot = _matchingSlot(bank.slots, await device.readActive());
      _draft = await device.readActive();
      _message = 'Banco restaurado';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Grava um modelo permanentemente na flash do pedal.
  ///
  /// [index] e o indice 0-based do slot de modelo (o mesmo valor que o preset
  /// guarda). O registro e montado por `model_flash.dart`.
  Future<void> saveModel({
    required ModelKind kind,
    required int index,
    required String name,
    required List<int> buffer,
    void Function(double progress)? onProgress,
  }) async {
    final device = _device;
    if (device == null) {
      throw StateError('Dispositivo nao conectado');
    }
    final isCab = kind == ModelKind.cab;
    final record = isCab
        ? encodeCabFlashRecord(buffer, name: name)
        : encodeAmpFlashRecord(buffer, name: name);
    final address = modelFlashAddress(isCab: isCab, index: index);
    if (_busy) {
      throw StateError('Outra operacao em andamento');
    }
    _busy = true;
    notifyListeners();
    try {
      await device.writeModelFlash(address, record, onProgress: onProgress);
      // O pedal regenera a tabela de nomes na hora; atualizar a copia local
      // evita uma releitura so para exibir o nome novo.
      _modelNames = _modelNames.withName(
        isCab: isCab,
        index: index,
        name: name,
      );
      _message = 'Modelo gravado em ${isCab ? 'CAB' : 'AMP'} ${index + 1}';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Le a flash inteira de modelos (245760 bytes).
  Future<List<int>> readModelFlashAll({
    void Function(double progress)? onProgress,
  }) async {
    final device = _device;
    if (device == null) {
      throw StateError('Dispositivo nao conectado');
    }
    if (_busy) {
      throw StateError('Outra operacao em andamento');
    }
    _busy = true;
    notifyListeners();
    try {
      final out = <int>[];
      while (out.length < modelFlashSize) {
        final chunk = await device.readBlock(
          modelFlashBase + out.length,
          maxRead < modelFlashSize - out.length
              ? maxRead
              : modelFlashSize - out.length,
          area: Area.model,
        );
        out.addAll(chunk);
        onProgress?.call(out.length / modelFlashSize);
      }
      _message = 'Flash de modelos lida';
      return out;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Regrava a flash de modelos a partir de um backup.
  ///
  /// Escreve so os blocos que diferem e confere cada um por releitura. Um
  /// backup de outra versao de firmware pode nao caber; nesse caso nada e
  /// escrito.
  Future<int> restoreModelFlashAll(
    List<int> data, {
    void Function(double progress)? onProgress,
  }) async {
    final device = _device;
    if (device == null) {
      throw StateError('Dispositivo nao conectado');
    }
    if (data.length != modelFlashSize) {
      throw FormatException(
        'Backup de modelos deve ter $modelFlashSize bytes, veio ${data.length}',
      );
    }
    if (_busy) {
      throw StateError('Outra operacao em andamento');
    }
    _busy = true;
    notifyListeners();
    var written = 0;
    try {
      const block = 8192;
      for (var offset = 0; offset < modelFlashSize; offset += block) {
        final want = data.sublist(offset, offset + block);
        final have = await device.readBlock(
          modelFlashBase + offset,
          block,
          area: Area.model,
        );
        if (_sameBytes(have, want)) {
          onProgress?.call((offset + block) / modelFlashSize);
          continue;
        }
        await device.writeModelFlash(modelFlashBase + offset, want);
        written++;
        onProgress?.call((offset + block) / modelFlashSize);
      }
      _message = written == 0
          ? 'Flash ja estava igual ao backup'
          : 'Flash de modelos restaurada ($written blocos)';
      return written;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> setBypass(bool value) =>
      _global(() => _device!.setBypass(value));
  Future<void> setLoopback(bool value) =>
      _global(() => _device!.setLoopback(value));
  Future<void> setTuner(bool value) => _global(() => _device!.setTuner(value));

  Future<void> _global(Future<void> Function() action) async {
    if (_device == null) return;
    await _guard(action);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _message = '$error';
      debugPrint('erro: $error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _lostSubscription?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}

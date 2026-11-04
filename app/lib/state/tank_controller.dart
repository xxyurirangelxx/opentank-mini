import 'package:flutter/foundation.dart';

import '../core/device/tank_device.dart';
import '../core/model/preset.dart';
import '../core/model/preset_bank.dart';
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

  TankConnectionState get state => _state;
  String get statusMessage => _message;
  PresetBank? get bank => _bank;
  Preset? get draft => _draft;
  int get activeSlot => _activeSlot;
  bool get busy => _busy;
  bool get connected => _state == TankConnectionState.connected;
  TankDevice? get device => _device;

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

  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    _state = TankConnectionState.idle;
    _message = '';
    _bank = null;
    _draft = null;
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
      _message = device.identity;
    });
  }

  int _matchingSlot(List<Preset> slots, Preset active) {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] == active) return i;
    }
    // Estado nao salvo: mantem o slot selecionado.
    return _activeSlot;
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
    });
  }

  /// Aplica uma alteracao ao rascunho e ao pedal.
  Future<void> apply(Preset next) async {
    final device = _device;
    final previous = _draft;
    if (previous == null) return;
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
      _message = 'Alteracao rejeitada: $error';
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
    _device?.disconnect();
    super.dispose();
  }
}

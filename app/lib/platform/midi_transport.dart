import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';

import '../core/protocol/packing.dart';
import '../core/transport/transport.dart';

/// Transporte por MIDI nativo (WinMM no Windows, ALSA/CoreMIDI nos demais).
///
/// Funciona com qualquer porta MIDI class-compliant; a Tank Mini aparece como
/// `USB-Midi`. O plugin entrega SysEx já remontado, com `F0`/`F7`.
class MidiTransport implements TankTransport {
  MidiTransport({required this.deviceName});

  /// Trecho do nome da porta procurado na enumeração.
  final String deviceName;

  final MidiCommand _command = MidiCommand();
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  StreamSubscription<MidiPacket>? _subscription;
  MidiDevice? _device;

  @override
  String get name => _device?.name ?? deviceName;

  /// Lista portas MIDI disponíveis.
  static Future<List<MidiDevice>> listDevices() async =>
      await MidiCommand().devices ?? const <MidiDevice>[];

  @override
  Future<void> open() async {
    final devices = await _command.devices ?? const <MidiDevice>[];
    final matches = devices
        .where(
          (MidiDevice d) =>
              d.name.toLowerCase().contains(deviceName.toLowerCase()) &&
              d.outputPorts.isNotEmpty,
        )
        .toList();
    if (matches.isEmpty) {
      throw TransportException('Porta MIDI "$deviceName" nao encontrada');
    }
    if (matches.length > 1) {
      throw TransportException(
        'Mais de uma porta corresponde a "$deviceName": '
        '${matches.map((MidiDevice d) => d.name).join(', ')}',
      );
    }
    _device = matches.single;
    await _command.connectToDevice(_device!);
    final stream = _command.onMidiPacketReceived;
    if (stream == null) {
      throw TransportException('Plataforma nao expoe pacotes MIDI');
    }
    _subscription = stream.listen((MidiPacket packet) {
      final data = packet.data;
      if (data.isEmpty) return;
      // Interessa apenas SysEx completo; o plugin entrega o frame com F0/F7,
      // mas o protocolo usa bytes crus, entao desempacota aqui.
      if (data.first != 0xF0 || data.last != 0xF7) return;
      final device = packet.device;
      if (_device != null && device.id != _device!.id) return;
      try {
        _incoming.add(decodeSysEx(data));
      } on FormatException {
        // Frame parcial ou de outro protocolo: ignora.
      }
    });
  }

  @override
  Future<void> send(List<int> raw) async {
    final device = _device;
    if (device == null) {
      throw TransportException('Transporte MIDI nao aberto');
    }
    final frame = toSysEx(raw);
    _command.sendData(Uint8List.fromList(frame), deviceId: device.id);
    // O envio nativo e fire-and-forget; o pedal responde em poucos ms.
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    final device = _device;
    if (device != null) {
      _command.disconnectDevice(device);
    }
    _device = null;
    await _incoming.close();
    _command.dispose();
  }
}

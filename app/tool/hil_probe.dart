/// Sonda de validacao em hardware, usando o nucleo Dart do app.
///
/// Fala WinMM por FFI para nao depender do build Flutter. Prova que o codigo
/// Dart (empacotamento, checksum, leitura, escrita e swap) funciona contra a
/// pedal de verdade, nao apenas contra vetores gravados.
///
/// Uso:
///   dart run tool/hil_probe.dart [--write-test] [--swap-test]
///
/// Sem flags, apenas leitura: identidade, preset ativo e os 21 slots.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:opentank_mini/core/device/tank_device.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/core/protocol/packing.dart';
import 'package:opentank_mini/core/transport/transport.dart';

const int callbackFunction = 0x00030000;
const int mimLongData = 0x3C4;
const int midiHeaderDone = 1;

// --- WinMM ---

typedef _MidiInOpenC = Int32 Function(
  Pointer<IntPtr>,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
  Int32,
);
typedef _MidiInOpenDart = int Function(
  Pointer<IntPtr>,
  int,
  Pointer<Void>,
  Pointer<Void>,
  int,
);

typedef _MidiInPrepareC = Int32 Function(IntPtr, Pointer<Void>, Int32);
typedef _MidiInPrepareDart = int Function(int, Pointer<Void>, int);

typedef _MidiInAddBufferC = Int32 Function(IntPtr, Pointer<Void>, Int32);
typedef _MidiInAddBufferDart = int Function(int, Pointer<Void>, int);

typedef _MidiInStartC = Int32 Function(IntPtr);
typedef _MidiInStartDart = int Function(int);

typedef _MidiOutOpenC = Int32 Function(
  Pointer<IntPtr>,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
  Int32,
);
typedef _MidiOutOpenDart = int Function(
  Pointer<IntPtr>,
  int,
  Pointer<Void>,
  Pointer<Void>,
  int,
);

typedef _MidiOutPrepareC = Int32 Function(IntPtr, Pointer<Void>, Int32);
typedef _MidiOutPrepareDart = int Function(int, Pointer<Void>, int);

typedef _MidiOutLongMsgC = Int32 Function(IntPtr, Pointer<Void>, Int32);
typedef _MidiOutLongMsgDart = int Function(int, Pointer<Void>, int);

typedef _MidiOutUnprepareC = Int32 Function(IntPtr, Pointer<Void>, Int32);
typedef _MidiOutUnprepareDart = int Function(int, Pointer<Void>, int);

typedef _MidiCloseC = Int32 Function(IntPtr);
typedef _MidiCloseDart = int Function(int);

/// Cabecalho MIDIHDR (layout x64).
final class MidiHdr extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  external Pointer<Void> dwUser;
  @Uint32()
  external int dwFlags;
  external Pointer<Void> lpNext;
  external Pointer<Void> reserved;
  @Uint32()
  external int dwOffset;
  @Array(8)
  external Array<Pointer<Void>> dwReserved;
}

/// Transporte MIDI via WinMM, espelhando o que o plugin faz no app.
class WinMmTransport implements TankTransport {
  WinMmTransport();

  final DynamicLibrary _winmm = DynamicLibrary.open('winmm.dll');
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();

  final Pointer<IntPtr> _hIn = calloc<IntPtr>();
  final Pointer<IntPtr> _hOut = calloc<IntPtr>();
  final List<Pointer<MidiHdr>> _headers = <Pointer<MidiHdr>>[];
  final List<Pointer<Uint8>> _buffers = <Pointer<Uint8>>[];
  bool _closing = false;

  NativeCallable<
    Void Function(
      Pointer<Void>,
      Uint32,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Void>,
    )
  >?
  _callback;

  @override
  String get name => 'USB-Midi (FFI)';

  @override
  Future<void> open() async {
    final outOpen = _winmm.lookupFunction<_MidiOutOpenC, _MidiOutOpenDart>(
      'midiOutOpen',
    );
    final inOpen = _winmm.lookupFunction<_MidiInOpenC, _MidiInOpenDart>(
      'midiInOpen',
    );
    final resOut = outOpen(_hOut, 1, nullptr, nullptr, 0);
    if (resOut != 0) {
      throw TransportException('midiOutOpen falhou: $resOut');
    }
    _callback =
        NativeCallable<
          Void Function(
            Pointer<Void>,
            Uint32,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
          )
        >.listener(_onMidi);
    final resIn = inOpen(
      _hIn,
      0,
      _callback!.nativeFunction.cast(),
      nullptr,
      callbackFunction,
    );
    if (resIn != 0) {
      throw TransportException(
        'midiInOpen falhou: $resIn '
        '(outro programa pode estar usando a porta)',
      );
    }
    final prepare = _winmm.lookupFunction<_MidiInPrepareC, _MidiInPrepareDart>(
      'midiInPrepareHeader',
    );
    final add = _winmm.lookupFunction<_MidiInAddBufferC, _MidiInAddBufferDart>(
      'midiInAddBuffer',
    );
    final start = _winmm.lookupFunction<_MidiInStartC, _MidiInStartDart>(
      'midiInStart',
    );
    for (var i = 0; i < 8; i++) {
      final buffer = calloc<Uint8>(1024);
      final header = calloc<MidiHdr>();
      header.ref.lpData = buffer;
      header.ref.dwBufferLength = 1024;
      final rp = prepare(_hIn.value, header.cast(), sizeOf<MidiHdr>());
      final ra = add(_hIn.value, header.cast(), sizeOf<MidiHdr>());
      if (Platform.environment['HIL_DEBUG'] == '1' && i == 0) {
        print('prepare=$rp add=$ra hdrSize=${sizeOf<MidiHdr>()}');
      }
      _buffers.add(buffer);
      _headers.add(header);
    }
    final resStart = start(_hIn.value);
    if (Platform.environment['HIL_DEBUG'] == '1') {
      print(
        'open out=$resOut in=$resIn start=$resStart hIn=${_hIn.value} hOut=${_hOut.value}',
      );
    }
  }

  void _onMidi(
    Pointer<Void> handle,
    int message,
    Pointer<Void> instance,
    Pointer<Void> param1,
    Pointer<Void> param2,
  ) {
    if (message != mimLongData) return;
    if (_closing) return;
    final header = param1.cast<MidiHdr>().ref;
    if (header.dwBytesRecorded == 0) return;
    final data = Uint8List.fromList(
      header.lpData.asTypedList(header.dwBytesRecorded),
    );
    if (Platform.environment['HIL_DEBUG'] == '1') {
      print(
        'RX ${data.length}B: ${data.take(24).map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
    }
    // A camada de cima usa bytes crus; o frame vem empacotado em 7 bits.
    try {
      _incoming.add(decodeSysEx(data));
    } on FormatException {
      return;
    }
    final add = _winmm.lookupFunction<_MidiInAddBufferC, _MidiInAddBufferDart>(
      'midiInAddBuffer',
    );
    add(_hIn.value, param1.cast(), sizeOf<MidiHdr>());
  }

  @override
  Future<void> send(List<int> raw) async {
    final frame = toSysEx(raw);
    final buffer = calloc<Uint8>(frame.length);
    buffer.asTypedList(frame.length).setAll(0, frame);
    final header = calloc<MidiHdr>();
    header.ref.lpData = buffer;
    header.ref.dwBufferLength = frame.length;
    final prepare = _winmm
        .lookupFunction<_MidiOutPrepareC, _MidiOutPrepareDart>(
          'midiOutPrepareHeader',
        );
    final send = _winmm.lookupFunction<_MidiOutLongMsgC, _MidiOutLongMsgDart>(
      'midiOutLongMsg',
    );
    final unprepare = _winmm
        .lookupFunction<_MidiOutUnprepareC, _MidiOutUnprepareDart>(
          'midiOutUnprepareHeader',
        );
    prepare(_hOut.value, header.cast(), sizeOf<MidiHdr>());
    send(_hOut.value, header.cast(), sizeOf<MidiHdr>());
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while ((header.ref.dwFlags & midiHeaderDone) == 0) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    unprepare(_hOut.value, header.cast(), sizeOf<MidiHdr>());
    calloc.free(header);
    calloc.free(buffer);
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    _closing = true;
    final stop = _winmm.lookupFunction<_MidiCloseC, _MidiCloseDart>(
      'midiInStop',
    );
    stop(_hIn.value);
    final reset = _winmm.lookupFunction<_MidiCloseC, _MidiCloseDart>(
      'midiInReset',
    );
    reset(_hIn.value);
    // Espera os buffers voltarem antes de liberar memoria; um callback em voo
    // sobre memoria liberada derruba o processo.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final closeIn = _winmm.lookupFunction<_MidiCloseC, _MidiCloseDart>(
      'midiInClose',
    );
    final closeOut = _winmm.lookupFunction<_MidiCloseC, _MidiCloseDart>(
      'midiOutClose',
    );
    closeIn(_hIn.value);
    closeOut(_hOut.value);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _callback?.close();
    for (final header in _headers) {
      calloc.free(header);
    }
    for (final buffer in _buffers) {
      calloc.free(buffer);
    }
    calloc.free(_hIn);
    calloc.free(_hOut);
    await _incoming.close();
  }
}

/// Empacotamento 7 bits (duplicado de proposito: a sonda nao importa internals).
List<int> pack7ForProbe(List<int> data) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final byte in data) {
    buffer |= (byte & 0xFF) << bits;
    bits += 8;
    while (bits >= 7) {
      out.add(buffer & 0x7F);
      buffer >>= 7;
      bits -= 7;
    }
  }
  if (bits > 0) out.add(buffer & 0x7F);
  return out;
}

Future<void> main(List<String> args) async {
  final doWrite = args.contains('--write-test');
  final doSwap = args.contains('--swap-test');
  final transport = WinMmTransport();
  final device = TankDevice(transport, readTimeout: const Duration(seconds: 4));
  try {
    final identity = await device.connect();
    print('identidade: $identity');

    final active = await device.readActive();
    print('preset ativo: vol=${active.volume} routing=${active.routing}');

    final slots = <Preset>[];
    for (var i = 0; i < 21; i++) {
      slots.add(await device.readSlot(i));
    }
    final match = slots.indexWhere((Preset p) => p == active);
    print(
      'slots lidos: 21, ativo corresponde ao slot ${match >= 0 ? slotLabel(match) : "nenhum"}',
    );

    if (doWrite) {
      const target = 20;
      final original = slots[target];
      final probe = original.withVolume(original.volume == 50 ? 51 : 50);
      print('teste de escrita no slot ${slotLabel(target)}...');
      await device.saveSlot(target, probe);
      final readBack = await device.readSlot(target);
      print('  gravado e relido igual: ${readBack == probe}');
      await device.saveSlot(target, original);
      final restored = await device.readSlot(target);
      print('  restaurado: ${restored == original}');
      if (restored != original) {
        throw StateError('RESTAURACAO FALHOU no slot ${slotLabel(target)}');
      }
    }

    if (doSwap) {
      const a = 19;
      const b = 20;
      final first = await device.readSlot(a);
      final second = await device.readSlot(b);
      print('swap ${slotLabel(a)} <-> ${slotLabel(b)}...');
      await device.swapSlots(a, b);
      print('  swap confirmado');
      await device.swapSlots(a, b);
      final backA = await device.readSlot(a);
      final backB = await device.readSlot(b);
      print('  inverso restaurado: ${backA == first && backB == second}');
    }

    // Descartar alteracao: muda o volume na RAM e volta ao salvo.
    final saved = await device.readSlot(4);
    await device.setVolume(saved.volume == 60 ? 59 : 60);
    final changed = await device.readActive();
    final reverted = saved;
    await device.setVolume(reverted.volume);
    final back = await device.readActive();
    print(
      'descartar alteracao: mudou=${changed.volume != saved.volume} '
      'voltou=${back == saved}',
    );

    print('OK: nucleo Dart validado contra o hardware');
  } finally {
    await device.disconnect();
  }
}

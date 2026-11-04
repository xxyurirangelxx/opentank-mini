import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/io/wav_file.dart';
import 'package:opentank_mini/core/model/model_format.dart';

Uint8List _wav({
  required int format,
  required int channels,
  required int bits,
  required List<int> data,
  int rate = 48000,
}) {
  final blockAlign = channels * (bits ~/ 8);
  final header = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add(_u32(36 + data.length))
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits)
    ..add(_u32(16))
    ..add(_u16(format))
    ..add(_u16(channels))
    ..add(_u32(rate))
    ..add(_u32(rate * blockAlign))
    ..add(_u16(blockAlign))
    ..add(_u16(bits))
    ..add('data'.codeUnits)
    ..add(_u32(data.length))
    ..add(data);
  return header.toBytes();
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

void main() {
  group('WavFile', () {
    test('le PCM 16 bits mono', () {
      final data = <int>[];
      for (final value in <int>[0, 16384, -16384, 32767]) {
        data.addAll(_u16(value & 0xFFFF));
      }
      final wav = WavFile.parse(
        _wav(format: 1, channels: 1, bits: 16, data: data),
      );
      expect(wav.sampleRate, 48000);
      expect(wav.channels, 1);
      expect(wav.data.length, 4);
      expect(wav.data[1], closeTo(0.5, 0.001));
      expect(wav.data[2], closeTo(-0.5, 0.001));
    });

    test('le o IR real de 24 bits', () {
      final bytes = File('test/fixtures/ir-sample.wav').readAsBytesSync();
      final wav = WavFile.parse(bytes);
      expect(wav.bitsPerSample, 24);
      expect(wav.channels, 1);
      expect(wav.sampleRate, 48000);
      expect(wav.data.length, 4967);
      expect(wav.peak, lessThanOrEqualTo(1.0));
      expect(wav.peak, greaterThan(0.5));
    });

    test('mistura estereo para mono', () {
      final data = <int>[];
      for (final pair in <List<int>>[
        [16384, -16384],
        [32767, 32767],
      ]) {
        data
          ..addAll(_u16(pair[0]))
          ..addAll(_u16(pair[1]));
      }
      final wav = WavFile.parse(
        _wav(format: 1, channels: 2, bits: 16, data: data),
      );
      expect(wav.data[0], closeTo(0.0, 0.001));
      expect(wav.data[1], closeTo(1.0, 0.001));
    });

    test('rejeita formato comprimido', () {
      expect(
        () => WavFile.parse(
          _wav(format: 0x55, channels: 1, bits: 16, data: <int>[0, 0]),
        ),
        throwsFormatException,
      );
    });

    test('toCabSamples devolve 2048 amostras de 3 bytes', () {
      final wav = WavFile.parse(
        File('test/fixtures/ir-sample.wav').readAsBytesSync(),
      );
      final samples = wav.toCabSamples();
      expect(samples.length, cabSampleCount * 3);
    });
  });

  group('model_format', () {
    test('detecta os magics', () {
      final amp = Uint8List(modelBufferSize)..setRange(0, 4, ampMagic);
      final cab = Uint8List(modelBufferSize)..setRange(0, 4, cabMagic);
      expect(detectModelKind(amp), ModelKind.amp);
      expect(detectModelKind(cab), ModelKind.cab);
      expect(detectModelKind(Uint8List(10)), ModelKind.unknown);
    });

    test('encodeCab monta o header verificado', () {
      final wav = WavFile.parse(
        File('test/fixtures/ir-sample.wav').readAsBytesSync(),
      );
      final buffer = encodeCab(wav.toCabSamples());
      expect(buffer.length, modelBufferSize);
      expect(buffer.sublist(0, 4), cabMagic);
      expect(buffer.sublist(16, 20), <int>[0x00, 0x00, 0x01, 0x32]);
      expect(buffer.sublist(20, 23), wav.toCabSamples().sublist(0, 3));
    });

    test('ida e volta do CAB preserva as amostras', () {
      // Amostras 24-bit sorteaveis dentro da faixa valida do campo (24 bits).
      final samples = <int>[];
      for (var i = 0; i < cabSampleCount; i++) {
        final value = (i * 7919) % 0x1000000;
        samples
          ..add(value & 0xFF)
          ..add((value >> 8) & 0xFF)
          ..add((value >> 16) & 0xFF);
      }
      final buffer = encodeCab(samples);
      expect(buffer.sublist(20, 20 + samples.length), samples);
      expect(
        decodeCabSamples(buffer)
            .map((int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF])
            .expand((List<int> v) => v)
            .toList(),
        samples,
      );
    });

    test('encodeAmp exige o magic', () {
      expect(() => encodeAmp(<int>[0, 0, 0, 0]), throwsFormatException);
    });

    test('encodeAmp preenche ate o tamanho do buffer', () {
      final am2 = <int>[...ampMagic, ...List<int>.filled(6200, 7)];
      final buffer = encodeAmp(am2);
      expect(buffer.length, modelBufferSize);
      expect(buffer[6203], 7);
      expect(buffer[6204], 0);
      expect(decodeAmpPayload(buffer).length, 6204);
    });

    test('encodeAmp rejeita arquivo grande demais', () {
      expect(
        () => encodeAmp(<int>[
          ...ampMagic,
          ...List<int>.filled(modelBufferSize, 1),
        ]),
        throwsFormatException,
      );
    });
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

import '../model/model_format.dart';

/// Leitura de arquivos WAV para importacao de IR.
///
/// Suporta PCM 8/16/24/32 bits e float 32/64, mono ou estereo, inclusive o
/// formato extensivel (`0xFFFE`) com subtipo PCM. Nao decodifica ambulacao
/// comprimida: apenas formatos lineares.
class WavFile {
  WavFile._(this.sampleRate, this.channels, this.bitsPerSample, this.data);

  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Amostras normalizadas em -1..1, mono.
  final List<double> data;

  /// Le o arquivo.
  factory WavFile.parse(List<int> bytes) {
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    if (_ascii(bytes, 0) != 'RIFF' || _ascii(bytes, 8) != 'WAVE') {
      throw const FormatException('Nao e um arquivo WAV');
    }
    var offset = 12;
    int? format;
    int? channels;
    int? rate;
    int? bits;
    int? blockAlign;
    final pcm = <int>[];
    while (offset + 8 <= bytes.length) {
      final id = _ascii(bytes, offset);
      final size = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ') {
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        rate = view.getUint32(body + 4, Endian.little);
        blockAlign = view.getUint16(body + 12, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26) {
          format = view.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        final end = math.min(body + size, bytes.length);
        pcm.addAll(bytes.sublist(body, end));
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    if (format == null || channels == null || rate == null || bits == null) {
      throw const FormatException('Cabecalho WAV incompleto');
    }
    if (format != 1 && format != 3) {
      throw FormatException('Formato WAV nao suportado: $format');
    }
    if (blockAlign == null || blockAlign <= 0) {
      throw const FormatException('blockAlign invalido');
    }
    final samples = _decode(pcm, format, bits, blockAlign, channels);
    return WavFile._(rate, channels, bits, samples);
  }

  static List<double> _decode(
    List<int> pcm,
    int format,
    int bits,
    int blockAlign,
    int channels,
  ) {
    final view = ByteData.sublistView(Uint8List.fromList(pcm));
    final frames = pcm.length ~/ blockAlign;
    final perChannel = <double>[];
    final bytesPerSample = bits ~/ 8;
    for (var f = 0; f < frames; f++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        final at = f * blockAlign + c * bytesPerSample;
        if (at + bytesPerSample > pcm.length) break;
        sum += _sample(view, at, format, bits);
      }
      perChannel.add(sum / channels);
    }
    return perChannel;
  }

  static double _sample(ByteData view, int at, int format, int bits) {
    if (format == 3) {
      if (bits == 32) {
        return view.getFloat32(at, Endian.little).clamp(-1.0, 1.0);
      }
      if (bits == 64) {
        return view.getFloat64(at, Endian.little).clamp(-1.0, 1.0);
      }
      throw FormatException('Float de $bits bits nao suportado');
    }
    switch (bits) {
      case 8:
        return (view.getUint8(at) - 128) / 128.0;
      case 16:
        return view.getInt16(at, Endian.little) / 32768.0;
      case 24:
        final raw =
            view.getUint8(at) |
            (view.getUint8(at + 1) << 8) |
            (view.getUint8(at + 2) << 16);
        final signed = raw >= 0x800000 ? raw - 0x1000000 : raw;
        return signed / 8388608.0;
      case 32:
        return view.getInt32(at, Endian.little) / 2147483648.0;
      default:
        throw FormatException('PCM de $bits bits nao suportado');
    }
  }

  static String _ascii(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  /// Converte para amostras PCM 24-bit little-endian, mono, com
  /// [cabSampleCount] amostras (truncando ou completando com zero).
  List<int> toCabSamples({int? count}) {
    final total = count ?? cabSampleCount;
    final out = <int>[];
    for (var i = 0; i < total; i++) {
      final value = i < data.length ? data[i] : 0.0;
      final scaled = (value * 8388607).round().clamp(-8388608, 8388607);
      final unsigned = scaled < 0 ? scaled + 0x1000000 : scaled;
      out
        ..add(unsigned & 0xFF)
        ..add((unsigned >> 8) & 0xFF)
        ..add((unsigned >> 16) & 0xFF);
    }
    return out;
  }

  /// Pico absoluto do arquivo (0..1).
  double get peak =>
      data.isEmpty ? 0.0 : data.map((double v) => v.abs()).reduce(math.max);
}

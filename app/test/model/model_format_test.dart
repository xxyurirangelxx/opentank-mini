import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/model_format.dart';

/// Arquivo AMP no formato do editor: magic + 14 bytes de nome + payload.
Uint8List _ampFile(String magic, {String name = '', int payload = 6204}) {
  final out = Uint8List(18 + payload);
  out.setRange(0, 4, magic.codeUnits);
  final bytes = name.codeUnits.take(14).toList();
  out.setRange(4, 4 + bytes.length, bytes);
  for (var i = 18; i < out.length; i++) {
    out[i] = (i * 7) & 0xFF;
  }
  return out;
}

void main() {
  group('magic de AMP', () {
    test('aceita qualquer versao AM<n>', () {
      for (final magic in <String>[
        'AM2\u0000',
        'AM3\u0000',
        'AM4\u0000',
        'AM5\u0000',
        'AM9\u0000',
      ]) {
        expect(isAmpMagic(magic.codeUnits), isTrue, reason: magic);
      }
    });

    test('recusa o que nao e AMP', () {
      expect(isAmpMagic('CAB\u0000'.codeUnits), isFalse);
      expect(isAmpMagic('AMX\u0000'.codeUnits), isFalse);
      expect(isAmpMagic('AM2'.codeUnits), isFalse, reason: 'curto demais');
      expect(isAmpMagic(<int>[]), isFalse);
    });

    test('le a versao', () {
      expect(ampVersion('AM2\u0000'.codeUnits), 2);
      expect(ampVersion('AM4\u0000'.codeUnits), 4);
      expect(ampVersion('CAB\u0000'.codeUnits), isNull);
    });
  });

  group('encodeAmp', () {
    test('aceita AM2 e normaliza o buffer de previa', () {
      final buffer = encodeAmp(_ampFile('AM2\u0000'));
      expect(buffer.length, modelBufferSize);
      expect(buffer.sublist(0, 4), ampMagic);
      expect(buffer.sublist(4, 18), List<int>.filled(14, 0));
    });

    test('aceita AM4 e mantem o payload', () {
      final file = _ampFile('AM4\u0000', name: '4RAT_OD');
      final buffer = encodeAmp(file);
      expect(buffer.length, modelBufferSize);
      // O buffer de previa usa AM2 e nao carrega nome.
      expect(buffer.sublist(0, 4), ampMagic);
      expect(buffer.sublist(4, 18), List<int>.filled(14, 0));
      // O payload a partir do offset 18 e preservado byte a byte.
      expect(buffer.sublist(18, file.length), file.sublist(18));
    });

    test('aceita uma versao futura (AM5)', () {
      final buffer = encodeAmp(_ampFile('AM5\u0000', name: 'NOVO'));
      expect(buffer.sublist(0, 4), ampMagic);
      expect(buffer.length, modelBufferSize);
    });

    test('recusa arquivo que nao e AMP', () {
      expect(() => encodeAmp(_ampFile('CAB\u0000')), throwsFormatException);
    });

    test('recusa arquivo maior que o buffer', () {
      expect(
        () => encodeAmp(_ampFile('AM4\u0000', payload: modelBufferSize)),
        throwsFormatException,
      );
    });
  });

  group('decodeAmpName', () {
    test('le o nome embutido do AM4', () {
      expect(decodeAmpName(_ampFile('AM4\u0000', name: '4RAT_OD')), '4RAT_OD');
    });

    test('AM2 sem nome devolve vazio', () {
      expect(decodeAmpName(_ampFile('AM2\u0000')), '');
    });

    test('nome com byte invalido e descartado', () {
      final file = _ampFile('AM4\u0000');
      file[4] = 0x01;
      expect(decodeAmpName(file), '');
    });
  });

  group('detectModelKind', () {
    test('reconhece AMP em qualquer versao', () {
      expect(detectModelKind(_ampFile('AM2\u0000')), ModelKind.amp);
      expect(detectModelKind(_ampFile('AM4\u0000')), ModelKind.amp);
    });

    test('reconhece CAB', () {
      final cab = Uint8List(64)..setRange(0, 4, cabMagic);
      expect(detectModelKind(cab), ModelKind.cab);
    });

    test('desconhecido quando o magic nao bate', () {
      expect(detectModelKind(Uint8List(64)), ModelKind.unknown);
    });
  });
}

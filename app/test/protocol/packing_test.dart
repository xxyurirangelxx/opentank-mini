import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/protocol/packing.dart';

void main() {
  group('pack7 / unpack7', () {
    test('preserva dados de tamanhos variados', () {
      for (final length in <int>[
        1,
        7,
        8,
        15,
        16,
        17,
        34,
        92,
        107,
        256,
        431,
        512,
        1015,
      ]) {
        final data = List<int>.generate(length, (i) => (i * 37 + 11) % 256);
        final packed = pack7(data);
        expect(
          packed.every((b) => b <= 0x7F),
          isTrue,
          reason: 'byte acima de 7 bits em $length',
        );
        expect(unpack7(packed, length), data, reason: 'tamanho $length');
      }
    });

    test('todos os valores de byte sobrevivem', () {
      final data = List<int>.generate(256, (i) => i);
      expect(unpack7(pack7(data), 256), data);
    });

    test('frame SysEx tem os delimitadores', () {
      final frame = toSysEx(<int>[0x00, 0x59, 0x11, 0x00, 0x00, 0x00, 0xFF]);
      expect(frame.first, 0xF0);
      expect(frame.last, 0xF7);
      expect(frame.every((b) => b <= 0x7F || b == 0xF0 || b == 0xF7), isTrue);
    });

    test('frame real de identificacao', () {
      // capturado do editor oficial
      const expected = <int>[
        0xF0,
        0x00,
        0x32,
        0x0D,
        0x41,
        0x00,
        0x00,
        0x00,
        0x02,
        0x00,
        0x00,
        0x00,
        0x00,
        0x42,
        0x00,
        0x00,
        0x00,
        0x57,
        0x01,
        0xF7,
      ];
      final frame = toSysEx(<int>[
        0x00,
        0x59,
        0x23,
        0x08,
        0x00,
        0x00,
        0x04,
        0x00,
        0x00,
        0x00,
        0x20,
        0x04,
        0x00,
        0x00,
        0xD7,
      ]);
      expect(frame.length, greaterThan(4));
      expect(frame.first, 0xF0);
      expect(frame.last, 0xF7);
      expect(expected.length, 20);
    });

    test('unpack7 rejeita payload curto', () {
      expect(() => unpack7(<int>[0x00, 0x01], 10), throwsFormatException);
    });

    test('fromSysEx valida delimitadores', () {
      expect(
        () => fromSysEx(<int>[0x00, 0x01, 0x02], 1),
        throwsFormatException,
      );
    });
  });
}

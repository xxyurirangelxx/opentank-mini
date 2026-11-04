import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/preset.dart';

Uint8List _preset() {
  final bytes = Uint8List(92);
  bytes[0] = 100;
  bytes.setRange(2, 8, <int>[0, 1, 5, 2, 3, 4]);
  bytes[8] = 1;
  bytes[9] = 0;
  bytes[13] = 1;
  bytes[14] = 2;
  bytes[15] = 7;
  bytes[19] = 4;
  for (final offset in Preset.parameterOffsets[Block.amp]!) {
    bytes[offset] = 50;
    bytes[offset + 1] = 0;
  }
  return bytes;
}

void main() {
  group('Preset', () {
    test('le campos do layout verificado', () {
      final preset = Preset.fromBytes(_preset());
      expect(preset.volume, 100);
      expect(preset.routing, <int>[0, 1, 5, 2, 3, 4]);
      expect(preset.isEnabled(Block.fx), isTrue);
      expect(preset.isEnabled(Block.amp), isFalse);
      expect(preset.isEnabled(Block.cab), isTrue);
      expect(preset.model(Block.fx), 2);
      expect(preset.model(Block.amp), 7);
      expect(preset.model(Block.cab), 4);
      expect(preset.parameter(32), 50);
    });

    test('alteracoes devolvem nova instancia', () {
      final original = Preset.fromBytes(_preset());
      final changed = original.withVolume(30);
      expect(original.volume, 100);
      expect(changed.volume, 30);
      expect(changed.bytes, isNot(same(original.bytes)));
    });

    test('volume fica na faixa 0..100', () {
      final preset = Preset.fromBytes(_preset());
      expect(preset.withVolume(-5).volume, 0);
      expect(preset.withVolume(500).volume, 100);
    });

    test('routing valida tamanho', () {
      final preset = Preset.fromBytes(_preset());
      expect(() => preset.withRouting(<int>[0, 1]), throwsArgumentError);
      expect(preset.withRouting(<int>[1, 0, 2, 3, 4, 5]).routing, <int>[
        1,
        0,
        2,
        3,
        4,
        5,
      ]);
    });

    test('parametro e uint16 little-endian', () {
      final preset = Preset.fromBytes(_preset());
      final changed = preset.withParameter(34, 300);
      expect(changed.bytes[34], 300 & 0xFF);
      expect(changed.bytes[35], 300 >> 8);
      expect(changed.parameter(34), 300);
    });

    test('modelo respeita a contagem do bloco', () {
      final preset = Preset.fromBytes(_preset());
      expect(preset.withModel(Block.fx, 99).model(Block.fx), 2);
      expect(preset.withModel(Block.amp, 99).model(Block.amp), 19);
    });

    test('igualdade compara os 92 bytes', () {
      final a = Preset.fromBytes(_preset());
      final b = Preset.copy(a);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == b.withVolume(1), isFalse);
    });

    test('rejeita tamanho errado', () {
      expect(() => Preset.fromBytes(<int>[0, 1, 2]), throwsArgumentError);
    });
  });

  group('rotulos de slot', () {
    test('cobre 1A ate 7C', () {
      expect(slotLabel(0), '1A');
      expect(slotLabel(1), '1B');
      expect(slotLabel(4), '2B');
      expect(slotLabel(20), '7C');
    });
  });
}

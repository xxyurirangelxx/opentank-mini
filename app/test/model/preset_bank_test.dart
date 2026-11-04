import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/core/model/preset_bank.dart';

void main() {
  late List<int> realBank;

  setUpAll(() {
    realBank = File('test/fixtures/sample-bank.atkm').readAsBytesSync();
  });

  group('PresetBank', () {
    test('le o backup real do M-EFCS', () {
      final bank = PresetBank.fromBytes(realBank);
      expect(bank.slots.length, 21);
      expect(bank.slots[0].volume, 0x63);
      expect(bank.slots[20].volume, 0x4B);
    });

    test('ida e volta preserva os bytes', () {
      final bank = PresetBank.fromBytes(realBank);
      expect(bank.toBytes(), realBank);
    });

    test('preset 2B tem os valores conhecidos', () {
      final preset = PresetBank.fromBytes(realBank).slots[4];
      expect(slotLabel(4), '2B');
      expect(preset.volume, 0x64);
      expect(preset.routing, <int>[0, 1, 5, 2, 3, 4]);
      expect(preset.isEnabled(Block.fx), isFalse);
      expect(preset.model(Block.amp), 4);
    });

    test('rejeita tamanho errado', () {
      expect(
        () => PresetBank.fromBytes(realBank.sublist(0, 100)),
        throwsFormatException,
      );
    });

    test('rejeita marcador ausente', () {
      final damaged = List<int>.of(realBank);
      damaged[damaged.length - 1] = 0xFF;
      expect(() => PresetBank.fromBytes(damaged), throwsFormatException);
    });

    test('withSlot nao altera o original', () {
      final bank = PresetBank.fromBytes(realBank);
      final changed = bank.withSlot(0, bank.slots[0].withVolume(1));
      expect(bank.slots[0].volume, 0x63);
      expect(changed.slots[0].volume, 1);
    });
  });

  group('PresetFile', () {
    test('le e escreve 92 bytes', () {
      final preset = PresetBank.fromBytes(realBank).slots[4];
      final bytes = PresetFile.toBytes(preset);
      expect(bytes.length, 92);
      expect(PresetFile.fromBytes(bytes), preset);
    });

    test('rejeita tamanho errado', () {
      expect(() => PresetFile.fromBytes(<int>[1, 2, 3]), throwsFormatException);
    });
  });
}

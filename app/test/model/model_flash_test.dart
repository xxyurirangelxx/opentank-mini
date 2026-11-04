import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/model_flash.dart';
import 'package:opentank_mini/core/model/model_format.dart';

Uint8List _ampBuffer() {
  final out = Uint8List(modelBufferSize)..setRange(0, 4, ampMagic);
  for (var i = 18; i < 8192; i++) {
    out[i] = (i * 7) & 0xFF;
  }
  return out;
}

Uint8List _cabBuffer({int samples = cabSampleCount}) {
  final out = Uint8List(modelBufferSize)..setRange(0, 4, cabMagic);
  out.setRange(18, 20, cabHeaderTail);
  for (var i = 0; i < samples * 3; i++) {
    out[20 + i] = (i * 13 + 5) & 0xFF;
  }
  return out;
}

void main() {
  group('enderecos na flash de modelos', () {
    test('AMP usa o bloco anterior ao indice', () {
      expect(modelFlashAddress(isCab: false, index: 1), 0x70000000);
      expect(modelFlashAddress(isCab: false, index: 20), 0x70000000 + 19 * 8192);
    });

    test('CAB usa metades de bloco a partir do bloco 20', () {
      expect(modelFlashAddress(isCab: true, index: 1), 0x70000000 + 20 * 8192);
      expect(
        modelFlashAddress(isCab: true, index: 2),
        0x70000000 + 20 * 8192 + 4096,
      );
      expect(
        modelFlashAddress(isCab: true, index: 3),
        0x70000000 + 21 * 8192,
      );
      expect(
        modelFlashAddress(isCab: true, index: 20),
        0x70000000 + 29 * 8192 + 4096,
      );
    });

    test('indice fora da faixa e recusado', () {
      expect(() => modelFlashAddress(isCab: false, index: 0), throwsRangeError);
      expect(() => modelFlashAddress(isCab: true, index: 21), throwsRangeError);
    });

    test('todos os 20 slots cabem na regiao', () {
      for (var i = 1; i <= modelSlotCount; i++) {
        for (final isCab in <bool>[false, true]) {
          final address = modelFlashAddress(isCab: isCab, index: i);
          final size = isCab ? cabFlashSlotSize : 8192;
          expect(address, greaterThanOrEqualTo(modelFlashBase));
          expect(
            address + size,
            lessThanOrEqualTo(modelFlashBase + modelFlashSize),
          );
        }
      }
    });
  });

  group('setores a apagar', () {
    test('registro de 8192 bytes cobre dois setores', () {
      final address = modelFlashAddress(isCab: false, index: 3);
      expect(eraseSectorsFor(address, 8192), <int>[
        address,
        address + 4096,
      ]);
    });

    test('registro alinhado a 4096 cobre um setor', () {
      final address = modelFlashAddress(isCab: true, index: 1);
      expect(eraseSectorsFor(address, 4096), <int>[address]);
    });

    test('registro na segunda metade nao invade o vizinho', () {
      final address = modelFlashAddress(isCab: true, index: 2);
      expect(eraseSectorsFor(address, 4096), <int>[address]);
    });
  });

  group('registros', () {
    test('AMP troca o magic AM2 por AM4 e grava o nome', () {
      final record = encodeAmpFlashRecord(_ampBuffer(), name: '1J120_CL');
      expect(record.length, 8192);
      expect(record.sublist(0, 4), factoryAmpMagic);
      expect(decodeFlashName(record), '1J120_CL');
      // O payload a partir do byte 18 nao muda.
      expect(record.sublist(18), _ampBuffer().sublist(18));
    });

    test('nome longo e truncado em 14 bytes', () {
      final record = encodeAmpFlashRecord(_ampBuffer(), name: 'ABCDEFGHIJKLMNOP');
      expect(decodeFlashName(record), 'ABCDEFGHIJKLMN');
    });

    test('CAB grava so 1024 amostras e header 02 40', () {
      final buffer = _cabBuffer();
      final record = encodeCabFlashRecord(buffer, name: '3MESA_412');
      expect(record.length, cabFlashSlotSize);
      expect(record.sublist(0, 4), factoryCabMagic);
      expect(record.sublist(18, 20), <int>[0x02, 0x40]);
      expect(decodeFlashName(record), '3MESA_412');
      expect(
        record.sublist(20, 20 + 1024 * 3),
        buffer.sublist(20, 20 + 1024 * 3),
        reason: 'a flash guarda metade das amostras do buffer',
      );
      expect(
        record.sublist(20 + 1024 * 3),
        everyElement(0),
        reason: 'o resto do setor fica zerado',
      );    });

    test('CAB rejeita buffer curto', () {
      expect(
        () => encodeCabFlashRecord(Uint8List(100), name: 'X'),
        throwsFormatException,
      );
    });

    test('AMP rejeita buffer curto', () {
      expect(
        () => encodeAmpFlashRecord(Uint8List(100), name: 'X'),
        throwsFormatException,
      );
    });

    test('nome de um registro real de fabrica e lido', () {
      final record = Uint8List(8192)..setRange(0, 4, factoryCabMagic);
      record.setRange(4, 4 + '13BGN412'.length, '13BGN412'.codeUnits);
      expect(decodeFlashName(record), '13BGN412');
    });
  });
}

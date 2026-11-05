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
    test('AMP usa o bloco do proprio indice (0-based)', () {
      expect(modelFlashAddress(isCab: false, index: 0), 0x70000000);
      expect(
        modelFlashAddress(isCab: false, index: 19),
        0x70000000 + 19 * 8192,
      );
    });

    test('CAB usa metades de bloco a partir do bloco 20', () {
      expect(modelFlashAddress(isCab: true, index: 0), 0x70000000 + 20 * 8192);
      expect(
        modelFlashAddress(isCab: true, index: 1),
        0x70000000 + 20 * 8192 + 4096,
      );
      expect(modelFlashAddress(isCab: true, index: 2), 0x70000000 + 21 * 8192);
      expect(
        modelFlashAddress(isCab: true, index: 19),
        0x70000000 + 29 * 8192 + 4096,
      );
    });

    test('indice fora da faixa e recusado', () {
      expect(
        () => modelFlashAddress(isCab: false, index: -1),
        throwsRangeError,
      );
      expect(() => modelFlashAddress(isCab: true, index: 20), throwsRangeError);
    });

    test('todos os 20 slots cabem na regiao', () {
      for (var i = 0; i < modelSlotCount; i++) {
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
      expect(eraseSectorsFor(address, 8192), <int>[address, address + 4096]);
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
      final record = encodeAmpFlashRecord(
        _ampBuffer(),
        name: 'ABCDEFGHIJKLMNOP',
      );
      expect(decodeFlashName(record), 'ABCDEFGHIJKLMN');
    });

    test('CAB grava amostras a partir do offset 20 e header 02 40', () {
      final buffer = _cabBuffer();
      final record = encodeCabFlashRecord(buffer, name: '3MESA_412');
      expect(record.length, cabFlashSlotSize);
      expect(record.sublist(0, 4), factoryCabMagic);
      expect(record.sublist(18, 20), <int>[0x02, 0x40]);
      expect(decodeFlashName(record), '3MESA_412');
      expect(
        record.sublist(20, 20 + cabFlashSampleBytes),
        buffer.sublist(20, 20 + cabFlashSampleBytes),
        reason: 'a flash guarda o maior trecho de amostras que cabe',
      );
    });

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

  group('tabela de nomes do pedal', () {
    test('decodifica registros de 14 bytes com NUL no fim', () {
      // Sequencia real lida de 0x90000000: registros de 14 bytes, nome curto
      // preenchido com NUL.
      final blob = <int>[
        ...'1J120_CL'.codeUnits,
        ...List<int>.filled(6, 0),
        ...'2J900_CL'.codeUnits,
        ...List<int>.filled(6, 0),
        ...'15CT-Gas V4H'.codeUnits,
        ...List<int>.filled(2, 0),
      ];
      expect(blob.length, nameTableRecordSize * 3);
      expect(decodeNameTable(blob), <String>[
        '1J120_CL',
        '2J900_CL',
        '15CT-Gas V4H',
      ]);
    });

    test('para no primeiro registro vazio', () {
      final blob = <int>[
        ...'1AC-SeVin'.codeUnits,
        ...List<int>.filled(5, 0),
        ...List<int>.filled(nameTableRecordSize + 40, 0),
      ];
      expect(decodeNameTable(blob), <String>['1AC-SeVin']);
    });

    test('leitura zerada devolve tabela vazia', () {
      expect(decodeNameTable(List<int>.filled(nameTableBytes, 0)), isEmpty);
    });

    test('registro com byte fora do ASCII e descartado', () {
      final blob = <int>[
        0x41,
        0x01,
        ...List<int>.filled(12, 0),
        ...'B'.codeUnits,
        ...List<int>.filled(13, 0),
      ];
      expect(decodeNameTable(blob), isEmpty);
    });

    test('nome do modelo usa indice 0-based', () {
      const names = ModelNames(
        amp: <String>['1J120_CL', '2J900_CL'],
        cab: <String>['1AC-SeVin'],
      );
      expect(names.name(isCab: false, index: 0), '1J120_CL');
      expect(names.name(isCab: false, index: 1), '2J900_CL');
      expect(names.name(isCab: true, index: 0), '1AC-SeVin');
      expect(names.name(isCab: true, index: 1), isNull);
      expect(names.name(isCab: false, index: -1), isNull);
    });

    test('withName troca so o modelo pedido', () {
      const names = ModelNames(amp: <String>['A', 'B'], cab: <String>['C']);
      final updated = names.withName(isCab: false, index: 1, name: 'NOVO');
      expect(updated.amp.sublist(0, 3), <String>['A', 'NOVO', '']);
      expect(updated.cab, <String>['C']);
      expect(names.amp, <String>['A', 'B'], reason: 'nao altera o original');
      expect(
        () => names.withName(isCab: false, index: 20, name: 'X'),
        throwsRangeError,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/model_catalog.dart';
import 'package:opentank_mini/core/model/preset.dart';

void main() {
  group('catalogo de modelos', () {
    test('cada bloco tem a contagem de modelos do pedal', () {
      expect(fxModels.length, Block.fx.modelCount);
      expect(modModels.length, Block.mod.modelCount);
      expect(dlyModels.length, Block.dly.modelCount);
      expect(revModels.length, Block.rev.modelCount);
    });

    test('nenhum modelo tem mais parametros que o preset reserva', () {
      for (final MapEntry<Block, List<ModelInfo>> entry
          in modelCatalog.entries) {
        final slots = Preset.parameterOffsets[entry.key]!.length;
        for (final ModelInfo model in entry.value) {
          expect(
            model.paramCount,
            lessThanOrEqualTo(slots),
            reason:
                '${entry.key.label} ${model.name} tem ${model.paramCount} '
                'parametros e o preset reserva $slots',
          );
          expect(model.paramCount, greaterThan(0));
        }
      }
    });

    test('nome vem do catalogo so onde o pedal nao tem tabela', () {
      expect(catalogModelName(Block.fx, 0), 'Noise gate');
      expect(catalogModelName(Block.dly, 4), 'Lofi');
      expect(catalogModelName(Block.rev, 5), 'Cloud');
      expect(catalogModelName(Block.mod, 6), 'AutoFilter');
      expect(catalogModelName(Block.amp, 0), isNull);
      expect(catalogModelName(Block.cab, 0), isNull);
      expect(catalogModelName(Block.fx, 3), isNull);
    });

    test('rotulos acompanham o modelo escolhido', () {
      expect(parameterLabelsFor(Block.fx, 2), <String>[
        'Gate',
        'Sustain',
        'Attack',
        'Level',
      ]);
      expect(parameterLabelsFor(Block.mod, 0), <String>[
        'Speed',
        'Depth',
        'Mix',
      ]);
      expect(parameterLabelsFor(Block.mod, 6), <String>[
        'Speed',
        'Min',
        'Max',
        'Mix',
        'Fb',
      ]);
      expect(parameterLabelsFor(Block.dly, 0).last, 'Pitch');
      expect(parameterLabelsFor(Block.rev, 3).last, 'Combs');
      expect(parameterLabelsFor(Block.amp, 7), ampParams);
      expect(parameterLabelsFor(Block.cab, 7), cabParams);
      expect(parameterLabelsFor(Block.mod, 99), isEmpty);
    });

    test('CAB mostra frequencia, o resto mostra 0..100', () {
      // Extremos da faixa informada pelo editor oficial.
      expect(parameterText(Block.cab, 0, 77), '77');
      expect(parameterText(Block.cab, 1, 0), '20 Hz');
      expect(parameterText(Block.cab, 1, 100), '300 Hz');
      expect(parameterText(Block.cab, 2, 0), '18.0k');
      expect(parameterText(Block.cab, 2, 100), '5.0k');
      expect(parameterText(Block.amp, 0, 42), '42');
      expect(parameterText(Block.dly, 0, 100), '100');
    });
  });
}

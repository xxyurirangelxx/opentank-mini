/// Nomes e parametros dos modelos de FX, MOD, DLY e REV.
///
/// O pedal **nao guarda** esses nomes: as unicas tabelas de texto na memoria
/// sao as de AMP (`0x90000000`) e CAB (`0x80000000`), e o resto de
/// `0x80000000`..`0xA0000000` e espelho delas. Os nomes abaixo sao os que o
/// editor oficial (M-EFCS) mostra, fornecidos pelo dono do aparelho a partir
/// da interface dele.
///
/// AMP e CAB nao entram aqui: os nomes vem do pedal (`TankDevice.readModelNames`)
/// e os parametros sao iguais em todos os modelos.
library;

import 'preset.dart';

/// Um modelo de bloco: nome exibido e rotulos dos parametros, na ordem dos
/// offsets do preset.
class ModelInfo {
  const ModelInfo(this.name, this.params);

  final String name;
  final List<String> params;

  int get paramCount => params.length;
}

/// Modelos de FX, na ordem do indice do preset (0 = o primeiro).
const List<ModelInfo> fxModels = <ModelInfo>[
  ModelInfo('Noise gate', <String>['Gate']),
  ModelInfo('Boost', <String>['Gate', 'Gain']),
  ModelInfo('Compress', <String>['Gate', 'Sustain', 'Attack', 'Level']),
];

/// Modelos de MOD.
const List<ModelInfo> modModels = <ModelInfo>[
  ModelInfo('Chorus', <String>['Speed', 'Depth', 'Mix']),
  ModelInfo('Phaser', <String>['Speed', 'ParamA', 'ParamB', 'Fb']),
  ModelInfo('Tremolo', <String>['Speed', 'Depth', 'Level']),
  ModelInfo('Flanger', <String>['Speed', 'Depth', 'Fb', 'Mix']),
  ModelInfo('Vibrato', <String>['Speed', 'Depth']),
  ModelInfo('Univibe', <String>['Speed', 'Depth', 'Mix']),
  ModelInfo('AutoFilter', <String>['Speed', 'Min', 'Max', 'Mix', 'Fb']),
];

/// Modelos de DLY.
const List<ModelInfo> dlyModels = <ModelInfo>[
  ModelInfo('Analog', <String>['Time', 'Fb', 'Mix', 'Phaser', 'Pitch']),
  ModelInfo('Duck', <String>['Time', 'Fb', 'Mix', 'Unpack', 'Speed', 'Depth']),
  ModelInfo('dTape', <String>['Time', 'Fb', 'Mix', 'Grit', 'Speed', 'Depth']),
  ModelInfo('Dual', <String>['Time', 'Fb', 'Mix', 'T-Mode', 'Speed', 'Depth']),
  ModelInfo('Lofi', <String>['Time', 'Fb', 'Mix', 'Grit', 'Speed', 'Depth']),
];

/// Modelos de REV.
const List<ModelInfo> revModels = <ModelInfo>[
  ModelInfo('Room', <String>['Decay', 'Mix', 'HPass', 'LPass', 'Depth']),
  ModelInfo('Hall', <String>['Decay', 'Mix', 'HPass', 'LPass', 'Depth']),
  ModelInfo('Swell', <String>['Decay', 'Mix', 'HPass', 'LPass', 'RiseT']),
  ModelInfo('Spring', <String>['Decay', 'Mix', 'HPass', 'LPass', 'Combs']),
  ModelInfo('Shimmer', <String>['Decay', 'Mix', 'Tone', 'Pitch', 'Amt']),
  ModelInfo('Cloud', <String>['Decay', 'Mix', 'HPass', 'LPass', 'Diff']),
];

/// Catalogo dos blocos com nomes fixos.
const Map<Block, List<ModelInfo>> modelCatalog = <Block, List<ModelInfo>>{
  Block.fx: fxModels,
  Block.mod: modModels,
  Block.dly: dlyModels,
  Block.rev: revModels,
};

/// Parametros globais do AMP.
const List<String> ampParams = <String>[
  'Gain',
  'Level',
  'Bass',
  'Mid',
  'Treble',
];

/// Parametros globais do CAB.
const List<String> cabParams = <String>['Level', 'Low Cut', 'High Cut'];

/// Nome de um modelo que nao vem do pedal, ou `null` quando o bloco e AMP/CAB
/// ou o indice esta fora da tabela.
String? catalogModelName(Block block, int index) {
  final models = modelCatalog[block];
  if (models == null || index < 0 || index >= models.length) return null;
  return models[index].name;
}

/// Rotulos dos parametros do bloco para o modelo [model] (indice do preset).
///
/// Lista vazia quando o modelo e desconhecido; a interface entao mostra os
/// offsets crus.
List<String> parameterLabelsFor(Block block, int model) {
  switch (block) {
    case Block.amp:
      return ampParams;
    case Block.cab:
      return cabParams;
    case Block.fx:
    case Block.mod:
    case Block.dly:
    case Block.rev:
      final models = modelCatalog[block]!;
      if (model < 0 || model >= models.length) return const <String>[];
      return models[model].params;
  }
}

/// Faixa exibida pelo M-EFCS para o Low Cut do CAB.
const int cabLowCutMin = 20;
const int cabLowCutMax = 300;

/// Faixa exibida pelo M-EFCS para o High Cut do CAB. O botao gira para baixo:
/// `0` no parametro corresponde a 18 kHz e `100` a 5 kHz.
const int cabHighCutMax = 18000;
const int cabHighCutMin = 5000;

/// Texto do valor de um parametro.
///
/// Quase todos os parametros sao 0..100 crus. A excecao e o CAB, onde o editor
/// oficial mostra frequencias: Low Cut de 20 a 300 Hz e High Cut de 18 kHz a
/// 5 kHz. A conversao e linear entre os extremos — o firmware pode usar outra
/// curva, mas os extremos e os valores intermediarios conferem com o editor.
String parameterText(Block block, int index, int raw) {
  if (block == Block.cab) {
    if (index == 1) {
      final hz = cabLowCutMin + (cabLowCutMax - cabLowCutMin) * raw ~/ 100;
      return '$hz Hz';
    }
    if (index == 2) {
      final hz = cabHighCutMax - (cabHighCutMax - cabHighCutMin) * raw ~/ 100;
      return hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)}k' : '$hz Hz';
    }
  }
  return '$raw';
}

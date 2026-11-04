import 'dart:typed_data';

import '../protocol/messages.dart';

/// Bloco de efeito da cadeia.
enum Block {
  fx('FX', 8, 14, 3),
  amp('AMP', 9, 15, 20),
  cab('CAB', 13, 19, 20),
  mod('MOD', 10, 16, 7),
  dly('DLY', 11, 17, 5),
  rev('REV', 12, 18, 6);

  const Block(
    this.label,
    this.toggleAddress,
    this.modelAddress,
    this.modelCount,
  );

  final String label;
  final int toggleAddress;
  final int modelAddress;
  final int modelCount;
}

/// Modulos na ordem canonica de exibicao.
const List<Block> blockOrder = <Block>[
  Block.fx,
  Block.amp,
  Block.cab,
  Block.mod,
  Block.dly,
  Block.rev,
];

/// Um preset de 92 bytes.
///
/// A classe e imutavel: alteracoes devolvem um novo preset, o que facilita
/// desfazer e descartar o rascunho sem tocar no estado salvo.
class Preset {
  Preset(this.bytes) : assert(bytes.length == presetSize);

  /// Copia de [other].
  Preset.copy(Preset other) : bytes = Uint8List.fromList(other.bytes);

  /// Preset vazio.
  factory Preset.empty() => Preset(Uint8List(presetSize));

  /// Le um preset de um bloco de bytes.
  factory Preset.fromBytes(List<int> data) {
    if (data.length != presetSize) {
      throw ArgumentError(
        'Preset precisa de $presetSize bytes, recebeu '
        '${data.length}',
      );
    }
    return Preset(Uint8List.fromList(data));
  }

  final Uint8List bytes;

  int get volume => bytes[0];

  Preset withVolume(int value) => _with(0, value.clamp(0, 100));

  /// Ordem dos blocos na cadeia (6 valores em `bytes[2..7]`).
  List<int> get routing => bytes.sublist(2, 8);

  Preset withRouting(List<int> order) {
    if (order.length != 6) {
      throw ArgumentError('Routing precisa de 6 posicoes');
    }
    final copy = _copy();
    copy.setRange(2, 8, order);
    return Preset(copy);
  }

  bool isEnabled(Block block) => bytes[block.toggleAddress] != 0;

  Preset withEnabled(Block block, bool enabled) =>
      _with(block.toggleAddress, enabled ? 1 : 0);

  int model(Block block) => bytes[block.modelAddress];

  Preset withModel(Block block, int index) =>
      _with(block.modelAddress, index.clamp(0, block.modelCount - 1));

  /// Valor de um parametro (uint16 little-endian).
  ///
  /// Todos os valores observados no aparelho estao em 0..100, mas o campo tem
  /// 16 bits; o limite de 0..100 e regra de interface, nao do formato.
  int parameter(int offset) => bytes[offset] | (bytes[offset + 1] << 8);

  Preset withParameter(int offset, int value) {
    final copy = _copy();
    final clamped = value.clamp(0, 0xFFFF);
    copy[offset] = clamped & 0xFF;
    copy[offset + 1] = (clamped >> 8) & 0xFF;
    return Preset(copy);
  }

  /// Limite pratico dos parametros nos presets de fabrica.
  static const int parameterMax = 100;

  /// Enderecos dos parametros de cada bloco.
  static const Map<Block, List<int>> parameterOffsets = <Block, List<int>>{
    Block.fx: <int>[20, 22, 24, 26],
    Block.amp: <int>[32, 34, 36, 38, 40],
    Block.cab: <int>[80, 82, 84],
    Block.mod: <int>[44, 46, 48, 50, 52, 54],
    Block.dly: <int>[56, 58, 60, 62, 64, 66],
    Block.rev: <int>[68, 70, 72, 74, 76, 78],
  };

  Preset _with(int offset, int value) {
    final copy = _copy();
    copy[offset] = value;
    return Preset(copy);
  }

  Uint8List _copy() => Uint8List.fromList(bytes);

  @override
  bool operator ==(Object other) {
    if (other is! Preset) return false;
    for (var i = 0; i < presetSize; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => 'Preset(vol=$volume, routing=$routing)';
}

/// Rotulo de um slot, no formato do pedal (`1A`, `1B`, ... `7C`).
String slotLabel(int index) {
  const banks = '1234567';
  const letters = 'ABC';
  return '${banks[index ~/ 3]}${letters[index % 3]}';
}

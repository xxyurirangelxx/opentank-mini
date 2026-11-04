import 'dart:typed_data';

import 'package:opentank_mini/core/model/preset.dart';

/// Formato do arquivo de banco completo (`.atkm`).
///
/// `21 * 92` bytes de presets seguidos do marcador `PATCHEND\0\0`, totalizando
/// 1942 bytes. O formato foi confirmado comparando um backup real do M-EFCS
/// com o dump independente lido do pedal.
class PresetBank {
  PresetBank(List<Preset> slots) : slots = List<Preset>.unmodifiable(slots) {
    if (slots.length != slotCount) {
      throw ArgumentError('Banco precisa de $slotCount slots');
    }
  }

  /// Marcador de fim do arquivo.
  static const List<int> marker = <int>[
    0x50,
    0x41,
    0x54,
    0x43,
    0x48,
    0x45,
    0x4E,
    0x44,
    0x00,
    0x00,
  ];

  /// Tamanho do arquivo `.atkm`.
  static const int fileSize = slotCount * presetSize + 10;

  static const int slotCount = 21;
  static const int presetSize = 92;

  final List<Preset> slots;

  /// Le um arquivo `.atkm`.
  factory PresetBank.fromBytes(List<int> data) {
    if (data.length != fileSize) {
      throw FormatException(
        'Arquivo .atkm deve ter $fileSize bytes, recebeu ${data.length}',
      );
    }
    final end = data.sublist(fileSize - 10);
    for (var i = 0; i < marker.length; i++) {
      if (end[i] != marker[i]) {
        throw const FormatException('Marcador PATCHEND ausente');
      }
    }
    return PresetBank(<Preset>[
      for (var i = 0; i < slotCount; i++)
        Preset.fromBytes(data.sublist(i * presetSize, (i + 1) * presetSize)),
    ]);
  }

  /// Serializa para `.atkm`.
  Uint8List toBytes() {
    final out = Uint8List(fileSize);
    for (var i = 0; i < slotCount; i++) {
      out.setRange(i * presetSize, (i + 1) * presetSize, slots[i].bytes);
    }
    out.setRange(slotCount * presetSize, fileSize, marker);
    return out;
  }

  /// Substitui um slot, devolvendo um novo banco.
  PresetBank withSlot(int index, Preset preset) {
    final copy = List<Preset>.of(slots);
    copy[index] = preset;
    return PresetBank(copy);
  }
}

/// Le e escreve um preset unico (`.tkm`).
class PresetFile {
  static const int size = 92;

  static Preset fromBytes(List<int> data) {
    if (data.length != size) {
      throw FormatException(
        'Arquivo .tkm deve ter $size bytes, recebeu ${data.length}',
      );
    }
    return Preset.fromBytes(data);
  }

  static Uint8List toBytes(Preset preset) => Uint8List.fromList(preset.bytes);
}

import 'dart:typed_data';

/// Áreas de memória da Tank Mini.
class Area {
  /// Banco de presets e RAM do preset ativo.
  static const int presets = 0x04;

  /// Buffer do modelo de AMP/CAB em edicao.
  static const int model = 0x05;
}

/// Comandos do protocolo.
class Command {
  static const int identify = 0x11;

  /// Apaga um setor da flash de modelos (ver `model_flash.dart`).
  static const int eraseSector = 0x21;
  static const int write = 0x22;
  static const int read = 0x23;
  static const int readReply = 0x23;
}

/// Endereco da RAM do preset ativo.
const int ramAddress = 0x10000000;

/// Tamanho de um preset.
const int presetSize = 92;

/// Quantidade de slots.
const int slotCount = 21;

/// Tamanho maximo de payload por leitura (resposta SysEx de 512 bytes).
const int maxRead = 431;

/// Tamanho maximo de payload por escrita verificada.
const int maxWrite = 1015;

/// Checksum: cobre de [start] ate o penultimo byte.
///
/// O calculo comeca no indice 5 porque o campo de comprimento (LE16 em 3..4)
/// transborda para o indice 4 acima de 247 bytes.
int checksum(List<int> raw) {
  var sum = 0;
  for (var i = 5; i < raw.length - 1; i++) {
    sum += raw[i];
  }
  return (255 - sum) % 256;
}

/// Aplica o checksum no ultimo byte.
Uint8List seal(List<int> raw) {
  final out = Uint8List.fromList(raw);
  out[out.length - 1] = checksum(out);
  return out;
}

/// Validacao do checksum de uma resposta.
bool isValidResponse(List<int> raw) {
  if (raw.length < 8) return false;
  return checksum(raw) == raw.last;
}

/// Requisicao de leitura.
Uint8List readRequest(int address, int length, {int area = Area.presets}) {
  final packet = <int>[0x00, 0x59, Command.read, 0x08, 0x00, 0x00, area];
  packet.addAll(_le32(address));
  packet.addAll(_le16(length));
  packet.add(0x00);
  packet.add(0x00);
  return seal(packet);
}

/// Requisicao de escrita.
Uint8List writeRequest(
  int address,
  List<int> payload, {
  int area = Area.presets,
}) {
  final size = payload.length;
  final packet = <int>[
    0x00,
    0x59,
    Command.write,
    ..._le16(size + 8),
    0x00,
    area,
    ..._le32(address),
    ..._le16(size),
    0x00,
    ...payload,
    0x00,
  ];
  return seal(packet);
}

/// Finaliza a gravacao na flash.
Uint8List commitRequest() => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x08,
  0x00,
  0x00,
  Area.presets,
  0x00,
  0x00,
  0x00,
  0xF0,
  0x00,
  0x00,
  0x00,
  0x00,
]);

/// Consulta de identificacao.
Uint8List identifyRequest() =>
    seal(<int>[0x00, 0x59, Command.identify, 0x00, 0x00, 0x00, 0xFF]);

/// Seleciona um slot.
Uint8List selectRequest(int slot) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.presets,
  slot,
  0x00,
  0x00,
  0xE0,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
]);

/// Liga/desliga um bloco, ou escolhe um modelo (mesmo endereco).
///
/// O endereco vai como LE32 `ramAddress + [offset]`.
Uint8List toggleRequest(int offset, int value) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.presets,
  ..._le32(ramAddress + offset),
  0x01,
  0x00,
  0x00,
  value & 0xFF,
  0x00,
]);

/// Altera um parametro (valor LE16).
///
/// O endereco vai como LE32 `ramAddress + [offset]`, igual ao toggle; o que
/// muda e o tipo (`02 00`) e o tamanho do valor.
Uint8List knobRequest(int offset, int value) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x0A,
  0x00,
  0x00,
  Area.presets,
  ..._le32(ramAddress + offset),
  0x02,
  0x00,
  0x00,
  ..._le16(value),
  0x00,
]);

/// Altera o routing da cadeia (6 bytes).
Uint8List routingRequest(List<int> order) {
  if (order.length != 6) {
    throw ArgumentError('Routing precisa de exatamente 6 bytes');
  }
  return seal(<int>[
    0x00,
    0x59,
    Command.write,
    0x0E,
    0x00,
    0x00,
    Area.presets,
    0x02,
    0x00,
    0x00,
    0x10,
    0x06,
    0x00,
    0x00,
    ...order,
    0x00,
  ]);
}

/// Ativa o preview do modelo carregado. [kind] 1 = AMP, 2 = CAB.
Uint8List previewModelRequest({required int kind}) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.model,
  0x00,
  0x00,
  0x00,
  0xA0,
  0x01,
  0x00,
  0x00,
  kind,
  0x00,
]);

/// Bypass global.
Uint8List bypassRequest(bool enabled) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.presets,
  0x02,
  0x00,
  0x00,
  0x20,
  0x01,
  0x00,
  0x00,
  enabled ? 1 : 0,
  0x00,
]);

/// Loopback global.
Uint8List loopbackRequest(bool enabled) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.presets,
  0x00,
  0x00,
  0x00,
  0xD0,
  0x01,
  0x00,
  0x00,
  enabled ? 1 : 0,
  0x00,
]);

/// Afinador.
Uint8List tunerRequest(bool enabled) => seal(<int>[
  0x00,
  0x59,
  Command.write,
  0x09,
  0x00,
  0x00,
  Area.presets,
  0x02,
  0x00,
  0x10,
  0x70,
  0x01,
  0x00,
  0x00,
  enabled ? 1 : 0,
  0x00,
]);

/// Consulta do estado global (bypass, loopback, afinador).
Uint8List globalStateRequest() => seal(<int>[
  0x00,
  0x59,
  Command.read,
  0x08,
  0x00,
  0x00,
  Area.presets,
  0x00,
  0x00,
  0x00,
  0x20,
  0x04,
  0x00,
  0x00,
  0x00,
]);

/// Consulta de estado do afinador.
Uint8List tunerStateRequest() => seal(<int>[
  0x00,
  0x59,
  Command.read,
  0x08,
  0x00,
  0x00,
  Area.presets,
  0x00,
  0x00,
  0x10,
  0x70,
  0x06,
  0x00,
  0x00,
  0x00,
]);

/// Apaga um setor de 4 KB da flash de modelos.
///
/// Formato capturado do "Restore Amp/Cab" do M-EFCS:
/// `00 59 21 05 00 00 05 <addr LE32> <cs>` (12 bytes). O `70` que fecha o
/// endereco de `0x70xxxxxx` e parte do proprio endereco, nao um campo extra.
Uint8List eraseSectorRequest(int address, {int area = Area.model}) =>
    seal(<int>[
      0x00,
      0x59,
      Command.eraseSector,
      0x05,
      0x00,
      0x00,
      area,
      ..._le32(address),
      0x00,
    ]);

/// Enderecos dos blocos no preset.
class BlockAddress {
  static const int fxToggle = 8;
  static const int ampToggle = 9;
  static const int modToggle = 10;
  static const int dlyToggle = 11;
  static const int revToggle = 12;
  static const int cabToggle = 13;
  static const int fxModel = 14;
  static const int ampModel = 15;
  static const int modModel = 16;
  static const int dlyModel = 17;
  static const int revModel = 18;
  static const int cabModel = 19;
}

List<int> _le16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> _le32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

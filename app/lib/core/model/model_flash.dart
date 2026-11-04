/// Gravacao permanente de modelos na flash do pedal (area `0x05`).
///
/// Descoberto instrumentando o "Restore AM4 Amp/Cab" do M-EFCS em 2026-11-04:
/// a flash de modelos fica em `0x70000000` e a gravacao e um apagamento por
/// setor seguido de escrita e um commit. O conteudo enviado pelo editor foi
/// comparado byte a byte com a leitura do pedal depois do restore: identico.
///
/// Layout da flash (245760 bytes = 30 blocos de 8192):
///
/// | Bloco | Conteudo |
/// |---|---|
/// | 0..19 | 20 AMPs, magic `AM4\0` + nome + dados |
/// | 20..29 | 20 CABs, magic `CAB\0`, **dois por bloco de 4096** |
///
/// Indices do preset sao 1-based: AMP `n` usa o bloco `n-1`; CAB `n` fica na
/// metade `(n-1) % 2` do bloco `20 + (n-1) ~/ 2`.
library;

import 'dart:typed_data';

/// Endereco base da flash de modelos.
const int modelFlashBase = 0x70000000;

/// Tamanho total da regiao de modelos.
const int modelFlashSize = 30 * 8192;

/// Tamanho de um setor de apagamento.
const int modelEraseSector = 4096;

/// Tamanho do bloco de um modelo CAB na flash (dois por bloco).
const int cabFlashSlotSize = 4096;

/// Quantidade de AMPs e CABs gravaveis.
const int modelSlotCount = 20;

/// Header de um modelo na flash de modelos de fabrica (`AM4\0`).
const List<int> factoryAmpMagic = <int>[0x41, 0x4D, 0x34, 0x00];

/// Header de um CAB na flash de modelos de fabrica (`CAB\0`).
const List<int> factoryCabMagic = <int>[0x43, 0x41, 0x42, 0x00];

/// Endereco do bloco (ou metade de bloco) de um modelo.
///
/// [index] e o valor guardado no preset, 1-based.
int modelFlashAddress({required bool isCab, required int index}) {
  if (index < 1 || index > modelSlotCount) {
    throw RangeError('Indice de modelo fora de 1..$modelSlotCount: $index');
  }
  if (!isCab) {
    return modelFlashBase + (index - 1) * 8192;
  }
  final block = 20 + (index - 1) ~/ 2;
  final half = (index - 1) % 2;
  return modelFlashBase + block * 8192 + half * cabFlashSlotSize;
}

/// Setores que precisam ser apagados para gravar [length] bytes em [address].
List<int> eraseSectorsFor(int address, int length) {
  final first = address ~/ modelEraseSector;
  final last = (address + length - 1) ~/ modelEraseSector;
  return <int>[for (var s = first; s <= last; s++) s * modelEraseSector];
}

/// Monta o registro de um AMP na flash (8192 bytes).
///
/// O formato de fabrica usa magic `AM4\0` seguido de um nome de 14 bytes e dos
/// dados. O buffer de previa (`AM2\0`) usa o mesmo payload, entao a conversao
/// aqui e so substituir o magic e preencher o nome.
Uint8List encodeAmpFlashRecord(
  List<int> buffer, {
  required String name,
}) {
  if (buffer.length < 8192) {
    throw FormatException('Buffer de AMP tem ${buffer.length} bytes');
  }
  final out = Uint8List(8192)..setRange(0, buffer.length, buffer);
  out.setRange(0, 4, factoryAmpMagic);
  out.setRange(4, 18, _nameBytes(name));
  return out;
}

/// Monta o registro de um CAB na flash (4096 bytes).
///
/// O buffer de previa guarda **2048 amostras** a partir do offset 20; a flash
/// guarda **1024 amostras** e o header de fabrica termina em `02 40` (1024) em
/// vez de `01 32` (50). O restante do setor e completado com zeros.
Uint8List encodeCabFlashRecord(
  List<int> buffer, {
  required String name,
}) {
  if (buffer.length < 20 + 1024 * 3) {
    throw FormatException('Buffer de CAB tem ${buffer.length} bytes');
  }
  final out = Uint8List(cabFlashSlotSize);
  out.setRange(0, 4, factoryCabMagic);
  out.setRange(4, 18, _nameBytes(name));
  out.setRange(18, 20, const <int>[0x02, 0x40]);
  out.setRange(20, 20 + 1024 * 3, buffer.sublist(20, 20 + 1024 * 3));
  return out;
}

/// Extrai o nome de um registro de modelo na flash.
String decodeFlashName(List<int> record) {
  final end = record.indexOf(0, 4);
  final limit = end == -1 || end > 18 ? 18 : end;
  final text = StringBuffer();
  for (var i = 4; i < limit; i++) {
    final c = record[i];
    if (c >= 0x20 && c < 0x7F) text.writeCharCode(c);
  }
  return text.toString();
}

Uint8List _nameBytes(String name) {
  final clean = name.trim();
  final out = Uint8List(14);
  for (var i = 0; i < clean.length && i < 14; i++) {
    out[i] = clean.codeUnitAt(i) & 0xFF;
  }
  return out;
}

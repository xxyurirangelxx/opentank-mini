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

/// Endereco da tabela de nomes de CAB que o pedal mantem na memoria.
const int cabNameTableAddress = 0x80000000;

/// Endereco da tabela de nomes de AMP que o pedal mantem na memoria.
const int ampNameTableAddress = 0x90000000;

/// Tamanho de um registro da tabela de nomes.
///
/// E o mesmo campo de 14 bytes do cabecalho do modelo na flash: o nome ocupa
/// o inicio do registro e o resto e preenchido com NUL.
const int nameTableRecordSize = 14;

/// Quantidade de nomes que cada tabela expoe.
const int nameTableCount = modelSlotCount;

/// Bytes que cobrem uma tabela inteira (20 x 14 = 280): cabe numa so leitura.
const int nameTableBytes = nameTableCount * nameTableRecordSize;

/// Header de um modelo na flash de modelos de fabrica (`AM4\0`).
const List<int> factoryAmpMagic = <int>[0x41, 0x4D, 0x34, 0x00];

/// Header de um CAB na flash de modelos de fabrica (`CAB\0`).
const List<int> factoryCabMagic = <int>[0x43, 0x41, 0x42, 0x00];

/// Endereco do bloco (ou metade de bloco) de um modelo.
///
/// [index] e o valor guardado no preset, **0-based**: o pedal guarda `0` para o
/// primeiro modelo de cada bloco.
///
/// A prova esta nos 21 presets de fabrica: o maior valor gravado e exatamente
/// `contagem - 1` nos seis blocos (FX 2 de 3, AMP 19 de 20, CAB 19 de 20,
/// MOD 6 de 7, DLY 4 de 5, REV 5 de 6), e ha presets com FX `0` e o FX ligado —
/// ou seja, `0` e um modelo e nao "sem modelo".
int modelFlashAddress({required bool isCab, required int index}) {
  if (index < 0 || index >= modelSlotCount) {
    throw RangeError(
      'Indice de modelo fora de 0..${modelSlotCount - 1}: $index',
    );
  }
  if (!isCab) {
    return modelFlashBase + index * 8192;
  }
  final block = 20 + index ~/ 2;
  final half = index % 2;
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
Uint8List encodeAmpFlashRecord(List<int> buffer, {required String name}) {
  if (buffer.length < 8192) {
    throw FormatException('Buffer de AMP tem ${buffer.length} bytes');
  }
  final out = Uint8List(8192)..setRange(0, buffer.length, buffer);
  out.setRange(0, 4, factoryAmpMagic);
  out.setRange(4, 18, _nameBytes(name));
  return out;
}

/// Tamanho do header de um CAB na flash.
const int cabFlashHeader = 20;

/// Bytes de amostra que cabem num CAB da flash (4096 - 20 = 4076, múltiplo de 3).
///
/// A flash guarda menos amostras que o buffer de prévia (2048). O número exato
/// que o firmware consome não foi determinado; gravar o máximo possível não
/// prejudica um IR mais curto, porque o excedente fica zerado no buffer.
const int cabFlashSampleBytes = (cabFlashSlotSize - cabFlashHeader) ~/ 3 * 3;

/// Monta o registro de um CAB na flash (4096 bytes).
///
/// Copia do offset 20 do buffer (onde começam as amostras) até o fim do setor.
/// O header de fábrica termina em `02 40`, diferente do `01 32` do buffer.
Uint8List encodeCabFlashRecord(List<int> buffer, {required String name}) {
  if (buffer.length < cabFlashHeader + cabFlashSampleBytes) {
    throw FormatException('Buffer de CAB tem ${buffer.length} bytes');
  }
  final out = Uint8List(cabFlashSlotSize);
  out.setRange(0, 4, factoryCabMagic);
  out.setRange(4, 18, _nameBytes(name));
  out.setRange(18, 20, const <int>[0x02, 0x40]);
  out.setRange(
    cabFlashHeader,
    cabFlashHeader + cabFlashSampleBytes,
    buffer.sublist(cabFlashHeader, cabFlashHeader + cabFlashSampleBytes),
  );
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

/// Decodifica uma tabela de nomes devolvida pelo pedal.
///
/// Os registros sao fixos de [nameTableRecordSize] bytes. A leitura para no
/// primeiro registro vazio ou invalido: um pedal que ainda nao respondeu
/// devolve zeros, e ai a tabela fica vazia em vez de virar uma lista de
/// strings em branco.
List<String> decodeNameTable(List<int> blob, {int limit = nameTableCount}) {
  final names = <String>[];
  for (
    var offset = 0;
    offset + nameTableRecordSize <= blob.length && names.length < limit;
    offset += nameTableRecordSize
  ) {
    final name = _decodeNameRecord(blob, offset);
    if (name == null) break;
    names.add(name);
  }
  return names;
}

String? _decodeNameRecord(List<int> blob, int offset) {
  final text = StringBuffer();
  for (var i = 0; i < nameTableRecordSize; i++) {
    final byte = blob[offset + i];
    if (byte == 0) break;
    // Fora do ASCII imprimivel so pode ser lixo de leitura.
    if (byte < 0x20 || byte > 0x7E) return null;
    text.writeCharCode(byte);
  }
  final value = text.toString().trim();
  return value.isEmpty ? null : value;
}

/// Nomes dos modelos que o pedal expoe: AMP e CAB.
///
/// Indices sao 0-based, iguais aos gravados no preset. Nao existe tabela
/// equivalente para FX, MOD, DLY e REV: varrendo `0x80000000`..`0xA0000000` o
/// pedal so devolve as duas tabelas abaixo, espelhadas (ver `PROTOCOL.md`).
class ModelNames {
  const ModelNames({this.amp = const <String>[], this.cab = const <String>[]});

  /// Nomes de AMP, indice 0 = primeiro modelo.
  final List<String> amp;

  /// Nomes de CAB, indice 0 = primeiro modelo.
  final List<String> cab;

  static const ModelNames empty = ModelNames();

  bool get isEmpty => amp.isEmpty && cab.isEmpty;

  List<String> table({required bool isCab}) => isCab ? cab : amp;

  /// Nome do modelo [index] (0-based), ou `null` quando o pedal nao informou.
  String? name({required bool isCab, required int index}) {
    final names = table(isCab: isCab);
    if (index < 0 || index >= names.length) return null;
    final value = names[index].trim();
    return value.isEmpty ? null : value;
  }

  /// Copia com o nome de um modelo trocado.
  ///
  /// Usado depois de gravar um modelo: o pedal regenera a tabela na hora, mas
  /// atualizar a copia local evita uma segunda leitura logo apos a gravacao.
  ModelNames withName({
    required bool isCab,
    required int index,
    required String name,
  }) {
    if (index < 0 || index >= nameTableCount) {
      throw RangeError(
        'Indice de modelo fora de 0..${nameTableCount - 1}: $index',
      );
    }
    final current = table(isCab: isCab);
    final next = <String>[
      for (var i = 0; i < nameTableCount; i++)
        i < current.length ? current[i] : '',
    ];
    next[index] = name;
    return isCab
        ? ModelNames(amp: amp, cab: next)
        : ModelNames(amp: next, cab: cab);
  }
}

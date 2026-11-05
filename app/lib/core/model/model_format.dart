/// Codificacao dos buffers de modelo (AMP e CAB) enviados em `area 0x05`.
///
/// Formatos derivados de capturas reais do editor oficial:
///
/// - AMP: magic `AM<n>\0`, header de 18 bytes, payload de 6204 bytes.
/// - CAB: magic `CAB\0`, header de 20 bytes, **2048 amostras PCM 24-bit LE**.
///
/// O firmware normaliza o IR: a forma de onda e preservada, mas a amplitude e
/// ajustada internamente. Por isso o buffer gerado aqui nao e identico ao que
/// o M-EFCS produz, embora toque corretamente no pedal.
library;

import 'dart:typed_data';

/// Tamanho total do buffer de modelo.
const int modelBufferSize = 8192;

/// Quantidade de amostras de um IR no formato CAB.
const int cabSampleCount = 2048;

/// Magic do AMP no buffer de previa (`AM2\0`).
///
/// O numero e a versao do formato. A M-VAVE publica versoes novas com
/// frequencia (AM2, AM4...), e o payload a partir do offset 18 e o mesmo entre
/// elas: muda o magic e, na flash, o campo de nome. Por isso a leitura aceita
/// qualquer `AM<n>` e a escrita normaliza para o que cada destino espera.
const List<int> ampMagic = <int>[0x41, 0x4D, 0x32, 0x00];

/// Magic do CAB.
const List<int> cabMagic = <int>[0x43, 0x41, 0x42, 0x00];

/// Constante do header CAB (`01 32`), igual em todas as capturas.
const List<int> cabHeaderTail = <int>[0x01, 0x32];

/// Identifica o tipo de modelo de um buffer lido do pedal.
enum ModelKind { amp, cab, unknown }

/// O buffer comeca com um magic de AMP (`AM` + digito + NUL)?
///
/// Aceita qualquer versao: `AM2\0`, `AM3\0`, `AM4\0` e as que vierem.
bool isAmpMagic(List<int> data) {
  if (data.length < 4) return false;
  return data[0] == 0x41 &&
      data[1] == 0x4D &&
      data[2] >= 0x30 &&
      data[2] <= 0x39 &&
      data[3] == 0x00;
}

/// Versao do formato AMP de um buffer (`2` para `AM2\0`), ou `null`.
int? ampVersion(List<int> data) => isAmpMagic(data) ? data[2] - 0x30 : null;

/// Detecta o tipo pelo magic.
ModelKind detectModelKind(List<int> buffer) {
  if (buffer.length >= 4) {
    if (isAmpMagic(buffer)) return ModelKind.amp;
    if (_startsWith(buffer, cabMagic)) return ModelKind.cab;
  }
  return ModelKind.unknown;
}

/// Monta o buffer de um AMP a partir de um arquivo `.am2Data`, `.am4Data`...
///
/// O arquivo ja vem no formato do pedal; so falta o padding ate 8192 bytes.
/// O magic e normalizado para `AM2\0` e o campo de nome e zerado, que e o que
/// o buffer de previa espera — o nome vai para a flash no momento de gravar.
Uint8List encodeAmp(List<int> data) {
  if (!isAmpMagic(data)) {
    throw const FormatException(
      'Arquivo AMP nao comeca com o magic AM<n> (AM2, AM4...)',
    );
  }
  if (data.length > modelBufferSize) {
    throw FormatException(
      'AMP tem ${data.length} bytes; o buffer aceita $modelBufferSize',
    );
  }
  final out = Uint8List(modelBufferSize)..setRange(0, data.length, data);
  out.setRange(0, 4, ampMagic);
  out.setRange(4, 18, List<int>.filled(14, 0));
  return out;
}

/// Nome embutido no cabecalho de um arquivo AMP, quando existe.
///
/// Arquivos `AM4` em diante trazem o nome nos bytes 4..18; os `AM2` deixam o
/// campo zerado. Devolve string vazia quando nao ha nome.
String decodeAmpName(List<int> data) {
  if (!isAmpMagic(data)) return '';
  final text = StringBuffer();
  for (var i = 4; i < 18 && i < data.length; i++) {
    final byte = data[i];
    if (byte == 0) break;
    if (byte < 0x20 || byte > 0x7E) return '';
    text.writeCharCode(byte);
  }
  return text.toString().trim();
}

/// Monta o buffer de um CAB a partir de amostras PCM 24-bit little-endian.
///
/// Aceita qualquer quantidade de amostras; o que passa de
/// [cabSampleCount] e descartado (o pedal usa 2048).
Uint8List encodeCab(List<int> samples24) {
  if (cabSampleCount * 3 > modelBufferSize - 20) {
    throw StateError('Layout CAB inconsistente');
  }
  final out = Uint8List(modelBufferSize)..setRange(0, 4, cabMagic);
  out.setRange(16, 18, const <int>[0x00, 0x00]);
  out.setRange(18, 20, cabHeaderTail);
  var cursor = 20;
  final limit = samples24.length < cabSampleCount * 3
      ? samples24.length
      : cabSampleCount * 3;
  for (var i = 0; i < limit; i++) {
    out[cursor++] = samples24[i] & 0xFF;
  }
  return out;
}

/// Le as amostras 24-bit de um buffer CAB lido do pedal.
List<int> decodeCabSamples(List<int> buffer) {
  if (detectModelKind(buffer) != ModelKind.cab) {
    throw const FormatException('Buffer nao e um CAB');
  }
  final out = <int>[];
  for (
    var i = 20;
    i + 2 < buffer.length && out.length < cabSampleCount;
    i += 3
  ) {
    out.add(buffer[i] | (buffer[i + 1] << 8) | (buffer[i + 2] << 16));
  }
  return out;
}

/// Le o payload de um AMP (sem o padding).
List<int> decodeAmpPayload(List<int> buffer) {
  if (detectModelKind(buffer) != ModelKind.amp) {
    throw const FormatException('Buffer nao e um AMP');
  }
  var last = buffer.length - 1;
  while (last > 18 && buffer[last] == 0) {
    last--;
  }
  return buffer.sublist(0, last + 1);
}

bool _startsWith(List<int> data, List<int> prefix) {
  if (data.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

/// Empacotamento de 8 para 7 bits usado pelo protocolo da Tank Mini.
///
/// O fluxo e continuo e little-endian: acumula 7 bits por byte e extrai um byte
/// sempre que ha 8 disponiveis. O ultimo grupo e completado com zeros.
library;

/// Empacota [data] no formato de 7 bits.
List<int> pack7(List<int> data) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final byte in data) {
    buffer |= (byte & 0xFF) << bits;
    bits += 8;
    while (bits >= 7) {
      out.add(buffer & 0x7F);
      buffer >>= 7;
      bits -= 7;
    }
  }
  if (bits > 0) {
    out.add(buffer & 0x7F);
  }
  return out;
}

/// Desempacota [data] de 7 bits, devolvendo [expectedLength] bytes.
List<int> unpack7(List<int> data, int expectedLength) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final byte in data) {
    buffer |= (byte & 0x7F) << bits;
    bits += 7;
    while (bits >= 8 && out.length < expectedLength) {
      out.add(buffer & 0xFF);
      buffer >>= 8;
      bits -= 8;
    }
    if (out.length >= expectedLength) {
      break;
    }
  }
  if (out.length != expectedLength) {
    throw FormatException(
      'Payload de 7 bits insuficiente: esperado $expectedLength, '
      'obtido ${out.length}',
    );
  }
  return out;
}

/// Envolve [raw] em um frame SysEx (F0 ... F7).
List<int> toSysEx(List<int> raw) => <int>[0xF0, ...pack7(raw), 0xF7];

/// Extrai o payload de um frame SysEx, dado o tamanho esperado em bytes.
List<int> fromSysEx(List<int> frame, int expectedLength) {
  if (frame.length < 4 || frame.first != 0xF0 || frame.last != 0xF7) {
    throw const FormatException('Frame SysEx invalido');
  }
  return unpack7(frame.sublist(1, frame.length - 1), expectedLength);
}

/// Decodifica um frame SysEx descobrindo o tamanho pelo próprio cabeçalho.
///
/// O campo de comprimento fica em `raw[3:5]` (LE16) e vale `payload + 8` em
/// todas as mensagens observadas. Por isso a mensagem inteira ocupa
/// `(raw[3] | raw[4] << 8) + 7` bytes.
List<int> decodeSysEx(List<int> frame) {
  if (frame.length < 4 || frame.first != 0xF0 || frame.last != 0xF7) {
    throw const FormatException('Frame SysEx invalido');
  }
  final packed = frame.sublist(1, frame.length - 1);
  final available = (packed.length * 7) ~/ 8;
  final head = unpack7(packed, available < 6 ? available : 6);
  if (head.length < 6) {
    return head;
  }
  final total = (head[3] | (head[4] << 8)) + 7;
  if (total > available) {
    throw FormatException(
      'Mensagem declara $total bytes, mas o frame so tem $available',
    );
  }
  return unpack7(packed, total);
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Utilitarios de leitura e gravacao de arquivos.
class PresetIO {
  /// Abre um arquivo e devolve os bytes, ou `null` se cancelado.
  static Future<List<int>?> open(String extension) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>[extension],
    );
    if (file == null) return null;
    return file.readAsBytes();
  }

  /// Salva os bytes e devolve uma referencia, ou `null` se cancelado.
  static Future<String?> save(
    List<int> data,
    String suggestedName,
    String extension,
  ) async {
    final uri = await FilePicker.saveFile(
      fileName: '$suggestedName.$extension',
      bytes: Uint8List.fromList(data),
      mimeType: 'application/octet-stream',
      dialogTitle: 'Salvar $extension',
    );
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }
}

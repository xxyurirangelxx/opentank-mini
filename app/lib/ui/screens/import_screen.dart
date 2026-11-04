import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/io/wav_file.dart';
import '../../core/model/model_flash.dart';
import '../../core/model/model_format.dart';
import '../../state/tank_controller.dart';
import '../theme.dart';

/// Tela de importacao de AMP e CAB.
///
/// O arquivo e enviado para o buffer de modelo do pedal (`area 0x05`) e
/// ativado por preview. Gravar de forma permanente no aparelho depende de um
/// comando que ainda nao foi capturado; por isso a tela deixa claro que a
/// operacao e de previa.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;
  List<int>? _buffer;
  ModelKind _kind = ModelKind.unknown;
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TankController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar AMP / CAB'),
        backgroundColor: AppTheme.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickAmp,
                  icon: const Icon(Icons.memory),
                  label: const Text('Carregar AMP (.am2Data)'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickCab,
                  icon: const Icon(Icons.graphic_eq),
                  label: const Text('Carregar CAB (.wav)'),
                ),
                const Spacer(),
                if (_buffer != null)
                  FilledButton.icon(
                    onPressed: _busy || !controller.connected
                        ? null
                        : () => _preview(controller),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Ouvir no pedal'),
                  ),
                if (_buffer != null) ...<Widget>[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy || !controller.connected
                        ? null
                        : () => _saveToDevice(controller),
                    icon: const Icon(Icons.save),
                    label: const Text('Gravar permanentemente'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_fileName != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _kind == ModelKind.amp ? Icons.memory : Icons.graphic_eq,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_fileName!)),
                    Text(
                      _kind == ModelKind.amp ? 'AMP' : 'CAB',
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_status.isNotEmpty)
              Text(
                _status,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
            const Spacer(),
            const _Notice(),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAmp() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['am2Data', 'am2', 'bin'],
    );
    if (file == null) return;
    await _load(
      file,
      convert: (List<int> data) => encodeAmp(data),
      kind: ModelKind.amp,
    );
  }

  Future<void> _pickCab() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['wav'],
    );
    if (file == null) return;
    await _load(
      file,
      convert: (List<int> data) =>
          encodeCab(WavFile.parse(data).toCabSamples()),
      kind: ModelKind.cab,
    );
  }

  Future<void> _load(
    PlatformFile file, {
    required List<int> Function(List<int>) convert,
    required ModelKind kind,
  }) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final bytes = await file.readAsBytes();
      final buffer = convert(bytes);
      setState(() {
        _buffer = buffer;
        _kind = kind;
        _fileName = file.name;
        _status = '';
      });
    } catch (error) {
      setState(() {
        _buffer = null;
        _fileName = null;
        _kind = ModelKind.unknown;
        _status = 'Nao foi possivel ler o arquivo: $error';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _preview(TankController controller) async {
    final buffer = _buffer;
    if (buffer == null) return;
    setState(() {
      _busy = true;
      _status = 'Enviando para o pedal...';
    });
    try {
      await controller.device!.uploadModel(
        buffer,
        previewKind: _kind == ModelKind.cab ? 2 : 1,
      );
      setState(
        () =>
            _status = 'Previa ativa. Ajuste os controles na pedal para ouvir.',
      );
    } catch (error) {
      setState(() => _status = 'Falha no envio: $error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveToDevice(TankController controller) async {
    final buffer = _buffer;
    if (buffer == null) return;
    final index = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          'Gravar ${_kind == ModelKind.cab ? 'CAB' : 'AMP'} em qual slot?',
        ),
        content: SizedBox(
          width: 420,
          height: 340,
          child: GridView.count(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: <Widget>[
              for (var i = 1; i <= modelSlotCount; i++)
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text('$i'),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (index == null) return;

    final name = (_fileName ?? 'OPEN TANK')
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '')
        .trim();
    setState(() {
      _busy = true;
      _status = 'Apagando e gravando...';
    });
    try {
      await controller.saveModel(
        kind: _kind,
        index: index,
        name: name.isEmpty ? 'OPEN TANK' : name,
        buffer: buffer,
        onProgress: (double value) {
          if (!mounted) return;
          setState(() => _status = 'Gravando... ${(value * 100).round()}%');
        },
      );
      if (!mounted) return;
      setState(
        () => _status =
            'Gravado no slot $index e conferido por releitura. '
            'Selecione o modelo no preset para usar.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha na gravacao: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: AppTheme.textDim),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'O envio coloca o modelo no buffer de previa do pedal. '
              'Gravar permanentemente apaga os setores da flash do slot e '
              'confere por releitura; o slot antigo e sobrescrito, entao '
              'guarde um backup antes.',
              style: TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

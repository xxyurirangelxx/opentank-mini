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
/// O arquivo pode ir para o buffer de previa do pedal (para ouvir antes) ou ser
/// gravado de forma permanente num dos 20 slots da flash de modelos.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;

  /// Nome embutido no arquivo (AM4 em diante). Vazio quando nao ha.
  String _embeddedName = '';
  List<int>? _buffer;
  ModelKind _kind = ModelKind.unknown;
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TankController>();
    final isAmp = _kind == ModelKind.amp;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: <Widget>[
            Icon(Icons.folder_open, size: 20),
            SizedBox(width: 10),
            Text('Importar AMP / CAB'),
          ],
        ),
        backgroundColor: AppTheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PickerCards(
                  busy: _busy,
                  onPickAmp: _pickAmp,
                  onPickCab: _pickCab,
                ),
                const SizedBox(height: 20),
                if (_buffer != null) ...<Widget>[
                  _FileCard(
                    name: _fileName ?? 'modelo',
                    isAmp: isAmp,
                    bytes: _buffer!.length,
                    busy: _busy,
                    connected: controller.connected,
                    onPreview: () => _preview(controller),
                    onSave: () => _saveToDevice(controller),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_busy) ...<Widget>[
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 10),
                ],
                if (_status.isNotEmpty)
                  Text(
                    _status,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 20),
                const _Notice(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAmp() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      // A M-VAVE publica versoes novas do formato com frequencia (AM2, AM4...).
      // O seletor lista as conhecidas; o conteudo e validado pelo magic, entao
      // uma versao futura com outro nome de extensao ainda entra por "bin".
      allowedExtensions: <String>[
        'am2Data',
        'am3Data',
        'am4Data',
        'am5Data',
        'am6Data',
        'am2',
        'am3',
        'am4',
        'am5',
        'am6',
        'bin',
      ],
    );
    if (file == null) return;
    await _load(
      file,
      convert: (List<int> data) => encodeAmp(data),
      kind: ModelKind.amp,
      // AM4 em diante traz o nome do modelo no cabecalho; usar esse nome e
      // melhor que o nome do arquivo, que costuma vir com sufixo de download.
      nameFrom: decodeAmpName,
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
    String Function(List<int>)? nameFrom,
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
        _embeddedName = nameFrom?.call(bytes) ?? '';
        _status = '';
      });
    } catch (error) {
      setState(() {
        _buffer = null;
        _fileName = null;
        _kind = ModelKind.unknown;
        _status = 'Não foi possível ler o arquivo: $error';
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
            _status = 'Prévia ativa. Ajuste os controles na pedal para ouvir.',
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
              for (var i = 0; i < modelSlotCount; i++)
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text('${i + 1}'),
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

    // O nome embutido no arquivo (AM4+) tem prioridade sobre o nome do
    // arquivo, que costuma vir com sufixo de download.
    final source = _embeddedName.isNotEmpty ? _embeddedName : (_fileName ?? '');
    final name = source
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
            'Gravado no slot ${index + 1} e conferido por releitura. '
            'Selecione o modelo no preset para usar.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha na gravação: $error');
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
        border: Border.all(color: AppTheme.stroke),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: AppTheme.textDim),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'O envio coloca o modelo no buffer de prévia do pedal. '
              'Gravar permanentemente apaga os setores da flash do slot e '
              'confere por releitura; o slot antigo e sobrescrito, então '
              'guarde um backup antes.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textDim,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dois cartoes de escolha de arquivo.
class _PickerCards extends StatelessWidget {
  const _PickerCards({
    required this.busy,
    required this.onPickAmp,
    required this.onPickCab,
  });

  final bool busy;
  final VoidCallback onPickAmp;
  final VoidCallback onPickCab;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final wide = constraints.maxWidth > 560;
        final gap = wide ? 14.0 : 0.0;
        final width = wide ? (constraints.maxWidth - gap) / 2 : double.infinity;
        final cards = <Widget>[
          SizedBox(
            width: width,
            child: _PickerCard(
              icon: Icons.memory,
              title: 'AMP',
              subtitle: 'Arquivo .am2Data, .am4Data... do editor oficial',
              onTap: busy ? null : onPickAmp,
            ),
          ),
          SizedBox(
            width: width,
            child: _PickerCard(
              icon: Icons.graphic_eq,
              title: 'CAB',
              subtitle: 'IR em .wav, convertido para 24 bits mono',
              onTap: busy ? null : onPickCab,
            ),
          ),
        ];
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[cards[0], const SizedBox(height: 12), cards[1]],
          );
        }
        return Row(
          children: <Widget>[
            cards[0],
            SizedBox(width: gap),
            cards[1],
          ],
        );
      },
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Container(
          height: 108,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textDim,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.upload_file, size: 18, color: AppTheme.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arquivo carregado, com as acoes de previa e gravacao.
class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.name,
    required this.isAmp,
    required this.bytes,
    required this.busy,
    required this.connected,
    required this.onPreview,
    required this.onSave,
  });

  final String name;
  final bool isAmp;
  final int bytes;
  final bool busy;
  final bool connected;
  final VoidCallback onPreview;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ready = !busy && connected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isAmp ? 'AMP' : 'CAB',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$bytes bytes',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.textDim),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: ready ? onPreview : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Ouvir no pedal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: ready ? onSave : null,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Gravar no pedal'),
                ),
              ),
            ],
          ),
          if (!connected) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'Conecte a pedal para enviar.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textDim),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/io/preset_io.dart';
import '../../core/model/preset_bank.dart';
import '../../state/tank_controller.dart';
import '../theme.dart';

/// Ajustes e utilitarios de arquivo.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TankController>();
    final bank = controller.bank;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: <Widget>[
            Icon(Icons.settings, size: 20),
            SizedBox(width: 10),
            Text('Ajustes e arquivos'),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Section(
                  icon: Icons.link,
                  title: 'Conexão',
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: controller.connected
                                ? AppTheme.success
                                : AppTheme.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            controller.connected
                                ? 'Conectado a ${controller.device?.identity ?? "Tank Mini"} '
                                      '(${controller.link == Link.usb ? "USB" : "Bluetooth"})'
                                : 'Desconectado',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.text,
                            ),
                          ),
                        ),
                        if (!controller.connected)
                          FilledButton.tonal(
                            onPressed: controller.connect,
                            child: const Text('Conectar'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  icon: Icons.grid_view_rounded,
                  title: 'Banco de presets',
                  description:
                      'O arquivo .atkm guarda os 21 slots. Exporte antes de '
                      'alterar o aparelho.',
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: bank == null ? null : _exportBank,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Salvar .atkm'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: controller.busy ? null : _importBank,
                          icon: const Icon(Icons.upload, size: 18),
                          label: const Text('Carregar .atkm'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  icon: Icons.memory,
                  title: 'Modelos (AMP e CAB)',
                  description:
                      'Backup completo da flash de modelos: 20 AMPs e 20 CABs. '
                      'Restaurar regrava só os blocos diferentes.',
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        FilledButton.tonalIcon(
                          onPressed: controller.busy || !controller.connected
                              ? null
                              : _exportModels,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Backup dos modelos'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: controller.busy || !controller.connected
                              ? null
                              : _importModels,
                          icon: const Icon(Icons.upload, size: 18),
                          label: const Text('Restaurar modelos'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_status.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.stroke),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.terminal,
                          size: 15,
                          color: AppTheme.textDim,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.stroke),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 17,
                        color: AppTheme.accent,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'OpenTank Mini não e afiliado a M-VAVE. Use por sua '
                          'conta e risco: grave um backup antes de alterar o '
                          'aparelho.',
                          style: TextStyle(
                            color: AppTheme.textDim,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportBank() async {
    final bank = context.read<TankController>().bank;
    if (bank == null) return;
    setState(() => _status = 'Exportando...');
    try {
      final path = await PresetIO.save(bank.toBytes(), 'tank-bank', 'atkm');
      if (!mounted) return;
      setState(() => _status = path == null ? 'Cancelado' : 'Salvo em $path');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha ao salvar: $error');
    }
  }

  Future<void> _exportModels() async {
    final controller = context.read<TankController>();
    setState(() => _status = 'Lendo a flash de modelos...');
    try {
      final data = await controller.readModelFlashAll(
        onProgress: (double v) {
          if (mounted) {
            setState(() => _status = 'Lendo... ${(v * 100).round()}%');
          }
        },
      );
      final path = await PresetIO.save(data, 'tank-models', 'otmodels');
      if (!mounted) return;
      setState(
        () => _status = path == null
            ? 'Cancelado'
            : 'Backup dos ${data.length} bytes salvo em $path',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha ao salvar: $error');
    }
  }

  Future<void> _importModels() async {
    setState(() => _status = 'Lendo arquivo...');
    try {
      final data = await PresetIO.open('otmodels');
      if (!mounted) return;
      if (data == null) {
        setState(() => _status = 'Cancelado');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Restaurar os modelos?'),
          content: const Text(
            'Os 20 AMPs e 20 CABs do arquivo sobrescrevem os do pedal. '
            'Blocos iguais são ignorados; os diferentes são apagados, '
            'gravados e conferidos um a um.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
      final controller = context.read<TankController>();
      final written = await controller.restoreModelFlashAll(
        data,
        onProgress: (double v) {
          if (mounted) {
            setState(() => _status = 'Restaurando... ${(v * 100).round()}%');
          }
        },
      );
      if (!mounted) return;
      setState(
        () => _status = written == 0
            ? 'A flash já estava igual ao arquivo'
            : '$written blocos regravados e conferidos',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha: $error');
    }
  }

  Future<void> _importBank() async {
    setState(() => _status = 'Lendo arquivo...');
    try {
      final data = await PresetIO.open('atkm');
      if (!mounted) return;
      if (data == null) {
        setState(() => _status = 'Cancelado');
        return;
      }
      final bank = PresetBank.fromBytes(data);
      final controller = context.read<TankController>();
      if (!controller.connected) {
        throw StateError('Conecte a pedal antes de escrever o banco');
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Sobrescrever os 21 slots?'),
          content: const Text(
            'Isso grava todos os presets do arquivo no aparelho. '
            'Exporte o banco atual antes, se ainda não fez.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gravar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await controller.restoreBank(bank);
      if (!mounted) return;
      setState(() => _status = 'Banco gravado e relido');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Falha: $error');
    }
  }
}

/// Bloco de ajustes com titulo, descricao e acoes.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.description,
  });

  final IconData icon;
  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: AppTheme.accent),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              description!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textDim,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

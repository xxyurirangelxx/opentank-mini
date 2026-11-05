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
        title: const Text('Ajustes e arquivos'),
        backgroundColor: AppTheme.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Conexao',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              controller.connected
                  ? 'Conectado a ${controller.device?.identity ?? "Tank Mini"}'
                  : 'Desconectado',
              style: const TextStyle(color: AppTheme.textDim),
            ),
            const SizedBox(height: 24),
            const Text(
              'Banco de presets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: bank == null ? null : _exportBank,
                  icon: const Icon(Icons.download),
                  label: const Text('Salvar .atkm'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: controller.busy ? null : _importBank,
                  icon: const Icon(Icons.upload),
                  label: const Text('Carregar .atkm'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Modelos (AMP e CAB)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: controller.busy || !controller.connected
                      ? null
                      : _exportModels,
                  icon: const Icon(Icons.download),
                  label: const Text('Backup dos modelos'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: controller.busy || !controller.connected
                      ? null
                      : _importModels,
                  icon: const Icon(Icons.upload),
                  label: const Text('Restaurar modelos'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_status.isNotEmpty)
              Text(
                _status,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
            const Spacer(),
            const Text(
              'OpenTank Mini nao e afiliado a M-VAVE. Use por sua conta e risco: '
              'grave um backup antes de alterar o aparelho.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ],
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
            'Blocos iguais sao ignorados; os diferentes sao apagados, '
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
            ? 'A flash ja estava igual ao arquivo'
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
            'Exporte o banco atual antes, se ainda nao fez.',
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

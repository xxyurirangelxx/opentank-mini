import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/model/preset.dart';
import '../../state/tank_controller.dart';
import '../theme.dart';
import '../widgets/block_panel.dart';
import '../widgets/chain_view.dart';
import '../widgets/slot_picker.dart';
import '../widgets/volume_bar.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

/// Tela principal: lista de slots, cadeia e editor do rascunho.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TankController>();
    return Scaffold(
      body: Row(
        children: <Widget>[
          const _SideBar(),
          const VerticalDivider(width: 1, color: AppTheme.surfaceHigh),
          Expanded(
            child: controller.connected
                ? const _Editor()
                : _ConnectPane(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      color: AppTheme.surface,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 16),
          const _SideButton(icon: Icons.tune, label: 'Editar', selected: true),
          _SideButton(
            icon: Icons.folder_open,
            label: 'Importar',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
            ),
          ),
          _SideButton(
            icon: Icons.settings,
            label: 'Ajustes',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.textDim;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: selected
            ? AppTheme.accentDim.withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(color: color, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectPane extends StatelessWidget {
  const _ConnectPane({required this.controller});

  final TankController controller;

  @override
  Widget build(BuildContext context) {
    final connecting = controller.state == TankConnectionState.connecting;
    final link = controller.link;
    return Center(
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              link == Link.usb ? Icons.usb : Icons.bluetooth,
              size: 64,
              color: AppTheme.textDim.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 20),
            Text(
              link == Link.usb
                  ? 'Conecte a Tank Mini por USB'
                  : 'Ligue o Bluetooth da Tank Mini',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              connecting
                  ? (link == Link.usb
                        ? 'Abrindo a porta MIDI...'
                        : 'Procurando o dispositivo BLE...')
                  : controller.statusMessage.isEmpty
                  ? (link == Link.usb
                        ? 'Feche outros editores que estejam usando a porta '
                              'MIDI.'
                        : 'Deixe a pedal ligada e perto do computador.')
                  : controller.statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (TankController.supportsUsb && !connecting)
              SegmentedButton<Link>(
                segments: const <ButtonSegment<Link>>[
                  ButtonSegment<Link>(
                    value: Link.usb,
                    label: Text('USB'),
                    icon: Icon(Icons.usb, size: 16),
                  ),
                  ButtonSegment<Link>(
                    value: Link.bluetooth,
                    label: Text('Bluetooth'),
                    icon: Icon(Icons.bluetooth, size: 16),
                  ),
                ],
                selected: <Link>{link},
                onSelectionChanged: (Set<Link> value) =>
                    controller.setLink(value.first),
              ),
            const SizedBox(height: 20),
            if (connecting)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              FilledButton.icon(
                onPressed: controller.connect,
                icon: const Icon(Icons.link),
                label: Text(
                  controller.state == TankConnectionState.error
                      ? 'Tentar novamente'
                      : 'Conectar',
                ),
              ),
            if (!TankController.supportsUsb) ...<Widget>[
              const SizedBox(height: 16),
              const Text(
                'Nesta plataforma o app usa apenas Bluetooth.',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TankController>();
    final draft = controller.draft;
    final bank = controller.bank;
    if (draft == null || bank == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: <Widget>[
        _Toolbar(controller: controller),
        if (controller.busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SlotPicker(
                      selected: controller.activeSlot,
                      slots: bank.slots,
                      onSelected: controller.busy
                          ? null
                          : controller.selectSlot,
                    ),
                    const SizedBox(width: 16),
                    if (controller.isDirty)
                      const Chip(
                        label: Text('nao salvo'),
                        visualDensity: VisualDensity.compact,
                      ),
                    const Spacer(),
                    Text(
                      controller.statusMessage,
                      style: const TextStyle(
                        color: AppTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                VolumeBar(
                  value: draft.volume,
                  onChanged: controller.busy
                      ? null
                      : (int v) => controller.apply(draft.withVolume(v)),
                ),
                const SizedBox(height: 20),
                ChainView(
                  order: draft.routing,
                  enabled: <Block, bool>{
                    for (final Block b in Block.values) b: draft.isEnabled(b),
                  },
                  onChanged: controller.busy
                      ? null
                      : (List<int> order) =>
                            controller.apply(draft.withRouting(order)),
                ),
                const SizedBox(height: 24),
                BlockPanel(
                  preset: draft,
                  onChanged: controller.busy ? null : controller.apply,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final TankController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Em janelas estreitas a barra rola em vez de estourar o layout.
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                children: <Widget>[
                  const Text(
                    'OpenTank Mini',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(width: 24),
                  _toolbarButton(
                    context,
                    icon: Icons.save,
                    label: 'Salvar',
                    onPressed: controller.busy || !controller.isDirty
                        ? null
                        : () => _confirmSave(context, controller),
                  ),
                  _toolbarButton(
                    context,
                    icon: Icons.save_as,
                    label: 'Salvar em...',
                    onPressed: controller.busy
                        ? null
                        : () => _saveTo(context, controller),
                  ),
                  _toolbarButton(
                    context,
                    icon: Icons.swap_horiz,
                    label: 'Trocar',
                    onPressed: controller.busy
                        ? null
                        : () => _swap(context, controller),
                  ),
                  _toolbarButton(
                    context,
                    icon: Icons.undo,
                    label: 'Descartar',
                    onPressed: controller.busy ? null : controller.revert,
                  ),
                  const SizedBox(width: 12),
                  _toggleChip('Bypass', controller.setBypass),
                  const SizedBox(width: 8),
                  _toggleChip('Loopback', controller.setLoopback),
                  const SizedBox(width: 8),
                  _toggleChip('Afinador', controller.setTuner),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Desconectar',
                    onPressed: controller.disconnect,
                    icon: const Icon(Icons.link_off, color: AppTheme.textDim),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolbarButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.text,
        disabledForegroundColor: AppTheme.textDim.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _toggleChip(String label, Future<void> Function(bool) action) {
    return _MomentaryToggle(
      label: label,
      onChanged: controller.busy ? null : action,
    );
  }

  Future<void> _confirmSave(
    BuildContext context,
    TankController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Salvar no slot?'),
        content: Text(
          'Gravar o estado atual em ${slotLabel(controller.activeSlot)}?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.save();
    }
  }

  Future<void> _saveTo(BuildContext context, TankController controller) async {
    final target = await _pickSlot(
      context,
      title: 'Salvar em qual slot?',
      confirm: 'Gravar',
      skip: controller.activeSlot,
    );
    if (target != null) {
      await controller.saveTo(target);
    }
  }

  Future<void> _swap(BuildContext context, TankController controller) async {
    final first = await _pickSlot(
      context,
      title: 'Trocar o slot...',
      confirm: 'Escolher o segundo',
    );
    if (first == null) return;
    if (!context.mounted) return;
    final second = await _pickSlot(
      context,
      title: '... com qual slot?',
      confirm: 'Trocar',
      skip: first,
    );
    if (second != null) {
      await controller.swap(first, second);
    }
  }

  Future<int?> _pickSlot(
    BuildContext context, {
    required String title,
    required String confirm,
    int? skip,
  }) {
    return showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(
          width: 420,
          height: 380,
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: <Widget>[
              for (var i = 0; i < 21; i++)
                if (i != skip)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, i),
                    child: Text(slotLabel(i)),
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
  }
}

/// Chip que ativa um recurso momentaneo (por exemplo aba do afinador).
class _MomentaryToggle extends StatefulWidget {
  const _MomentaryToggle({required this.label, required this.onChanged});

  final String label;
  final Future<void> Function(bool)? onChanged;

  @override
  State<_MomentaryToggle> createState() => _MomentaryToggleState();
}

class _MomentaryToggleState extends State<_MomentaryToggle> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(widget.label),
      selected: _on,
      onSelected: widget.onChanged == null
          ? null
          : (bool value) async {
              setState(() => _on = value);
              await widget.onChanged!(value);
            },
      selectedColor: AppTheme.accentDim,
      checkmarkColor: AppTheme.accent,
    );
  }
}

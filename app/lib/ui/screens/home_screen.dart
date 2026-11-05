import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/model/preset.dart';
import '../../state/tank_controller.dart';
import '../theme.dart';
import '../widgets/block_panel.dart';
import '../widgets/chain_view.dart';
import '../widgets/connection_badge.dart';
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
          Expanded(
            child: controller.connected || controller.bank != null
                ? const _Editor()
                : _ConnectPane(controller: controller),
          ),
        ],
      ),
    );
  }
}

/// Menu lateral, com icone e rotulo.
///
/// Tudo aqui tem a mesma largura util (68 px) e o mesmo alinhamento central:
/// o logo, os itens e o indicador da esquerda. A versao anterior misturava um
/// logo de 44 px com itens de largura livre, o que deixava as colunas
/// desencontradas na captura.
class _SideBar extends StatelessWidget {
  const _SideBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.stroke)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 16),
          const _Logo(),
          const SizedBox(height: 20),
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

/// Marca do app, no topo do menu.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'OpenTank Mini',
      child: Container(
        width: 56,
        height: 56,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.stroke),
        ),
        child: Image.asset(
          'assets/images/logo-symbol.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppTheme.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: color, size: 21),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
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
    final failed = controller.state == TankConnectionState.error;
    final link = controller.link;
    final usb = link == Link.usb;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 34, 32, 30),
            decoration: AppTheme.card(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: usb ? AppTheme.accentSoft : AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    usb ? Icons.usb : Icons.bluetooth,
                    size: 32,
                    color: usb ? AppTheme.accent : AppTheme.textDim,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  usb
                      ? 'Conecte a Tank Mini por USB'
                      : 'Ligue o Bluetooth da Tank Mini',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  connecting
                      ? (usb
                            ? 'Abrindo a porta MIDI...'
                            : 'Procurando o dispositivo BLE...')
                      : failed
                      ? controller.statusMessage
                      : (usb
                            ? 'Feche outros editores que estejam usando a '
                                  'porta MIDI.'
                            : 'Deixe a pedal ligada e perto do computador.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: failed ? AppTheme.danger : AppTheme.textDim,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                if (TankController.supportsUsb && !connecting)
                  SegmentedButton<Link>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppTheme.accentSoft,
                      selectedForegroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.textDim,
                      side: const BorderSide(color: AppTheme.stroke),
                    ),
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
                const SizedBox(height: 22),
                if (connecting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: controller.connect,
                      icon: Icon(failed ? Icons.refresh : Icons.link),
                      label: Text(failed ? 'Tentar novamente' : 'Conectar'),
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SlotHeader(controller: controller, draft: draft),
                    const SizedBox(height: 14),
                    VolumeBar(
                      value: draft.volume,
                      onChanged: controller.busy
                          ? null
                          : (int v) => controller.apply(draft.withVolume(v)),
                    ),
                    const SizedBox(height: 14),
                    _ChainCard(controller: controller, draft: draft),
                    const SizedBox(height: 18),
                    BlockPanel(
                      preset: draft,
                      onChanged: controller.busy ? null : controller.apply,
                      modelNames: <Block, List<String>>{
                        for (final Block b in Block.values)
                          b: controller.modelNamesFor(b),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Faixa com slot, estado de gravacao e resumo.
class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.controller, required this.draft});

  final TankController controller;
  final Preset draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: AppTheme.card(highlighted: controller.isDirty),
      child: Row(
        children: <Widget>[
          SlotPicker(
            selected: controller.activeSlot,
            slots: controller.bank!.slots,
            matched: controller.matchedSlot != null,
            onSelected: controller.busy ? null : controller.selectSlot,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (controller.isDirty)
                  const _StatusPill(
                    icon: Icons.edit_outlined,
                    label: 'não salvo',
                    color: AppTheme.accent,
                  )
                else
                  const _StatusPill(
                    icon: Icons.check_circle_outline,
                    label: 'salvo',
                    color: AppTheme.textDim,
                  ),
                Text(
                  controller.statusMessage,
                  style: const TextStyle(
                    color: AppTheme.textDim,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.controller, required this.draft});

  final TankController controller;
  final Preset draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.account_tree_outlined,
                size: 15,
                color: AppTheme.textDim,
              ),
              const SizedBox(width: 7),
              const Text(
                'CADEIA',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppTheme.textDim,
                ),
              ),
              const Spacer(),
              Text(
                'arraste para reordenar',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.textDim.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
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
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final TankController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.stroke)),
      ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConnectionBadge(controller: controller),
                  const SizedBox(width: 20),
                  _toolbarButton(
                    icon: Icons.save_outlined,
                    label: 'Salvar',
                    onPressed: controller.busy || !controller.isDirty
                        ? null
                        : () => _confirmSave(context, controller),
                  ),
                  _toolbarButton(
                    icon: Icons.save_as_outlined,
                    label: 'Salvar em...',
                    onPressed: controller.busy
                        ? null
                        : () => _saveTo(context, controller),
                  ),
                  _toolbarButton(
                    icon: Icons.swap_horiz,
                    label: 'Trocar',
                    onPressed: controller.busy
                        ? null
                        : () => _swap(context, controller),
                  ),
                  _toolbarButton(
                    icon: Icons.undo,
                    label: 'Descartar',
                    onPressed: controller.busy ? null : controller.revert,
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 26, color: AppTheme.stroke),
                  const SizedBox(width: 10),
                  _toggleChip(Icons.block, 'Bypass', controller.setBypass),
                  const SizedBox(width: 8),
                  _toggleChip(Icons.repeat, 'Loopback', controller.setLoopback),
                  const SizedBox(width: 8),
                  _toggleChip(Icons.tune, 'Afinador', controller.setTuner),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Desconectar',
                    onPressed: controller.disconnect,
                    icon: const Icon(
                      Icons.link_off,
                      color: AppTheme.textDim,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.text,
          disabledForegroundColor: AppTheme.textDim.withValues(alpha: 0.38),
        ),
      ),
    );
  }

  Widget _toggleChip(
    IconData icon,
    String label,
    Future<void> Function(bool) action,
  ) {
    return _MomentaryToggle(
      icon: icon,
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
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        content: SizedBox(
          width: 420,
          height: 380,
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: <Widget>[
              for (var i = 0; i < 21; i++)
                if (i != skip)
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, i),
                    child: Text(
                      slotLabel(i),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
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

/// Chip que ativa um recurso momentaneo (aba do afinador, loopback, bypass).
class _MomentaryToggle extends StatefulWidget {
  const _MomentaryToggle({
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final IconData icon;
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
      avatar: Icon(
        widget.icon,
        size: 15,
        color: _on ? AppTheme.accent : AppTheme.textDim,
      ),
      label: Text(
        widget.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _on ? AppTheme.accent : AppTheme.text,
        ),
      ),
      selected: _on,
      showCheckmark: false,
      onSelected: widget.onChanged == null
          ? null
          : (bool value) async {
              setState(() => _on = value);
              await widget.onChanged!(value);
            },
    );
  }
}

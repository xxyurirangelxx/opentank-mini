import 'package:flutter/material.dart';

import '../../core/model/model_catalog.dart';
import '../../core/model/preset.dart';
import '../theme.dart';

/// Icone de cada bloco da cadeia.
///
/// Um unico lugar decide o desenho do bloco: a cadeia, as abas e o cabecalho do
/// painel mostram sempre o mesmo simbolo.
IconData blockIcon(Block block) {
  switch (block) {
    case Block.fx:
      return Icons.auto_fix_high;
    case Block.amp:
      return Icons.graphic_eq;
    case Block.cab:
      return Icons.speaker;
    case Block.mod:
      return Icons.waves;
    case Block.dly:
      return Icons.timelapse;
    case Block.rev:
      return Icons.blur_on;
  }
}

/// Painel de edicao de um bloco: liga/desliga, modelo e parametros.
class BlockPanel extends StatefulWidget {
  const BlockPanel({
    super.key,
    required this.preset,
    required this.onChanged,
    this.modelNames = const <Block, List<String>>{},
    this.initialBlock,
  });

  final Preset preset;
  final ValueChanged<Preset>? onChanged;

  /// Nomes de modelo vindos do pedal, na ordem do indice do preset.
  ///
  /// Blocos sem tabela no pedal ficam de fora do mapa; o catalogo cobre o resto.
  final Map<Block, List<String>> modelNames;

  /// Bloco aberto ao montar.
  final Block? initialBlock;

  @override
  State<BlockPanel> createState() => _BlockPanelState();
}

class _BlockPanelState extends State<BlockPanel> {
  late Block _selected = widget.initialBlock ?? Block.fx;

  @override
  void didUpdateWidget(BlockPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wanted = widget.initialBlock;
    if (wanted != null && wanted != oldWidget.initialBlock) {
      _selected = wanted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _BlockTabs(
          selected: _selected,
          preset: preset,
          onSelected: (Block block) => setState(() => _selected = block),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: AppTheme.card(),
            child: _BlockEditor(
              key: ValueKey<Block>(_selected),
              block: _selected,
              preset: preset,
              modelNames: widget.modelNames,
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Abas horizontais dos seis blocos, com icone, nome e marca de ligado.
class _BlockTabs extends StatelessWidget {
  const _BlockTabs({
    required this.selected,
    required this.preset,
    required this.onSelected,
  });

  final Block selected;
  final Preset preset;
  final ValueChanged<Block> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final Block block in blockOrder)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _BlockTab(
                key: ValueKey<String>('block-tab-${block.label}'),
                block: block,
                selected: block == selected,
                enabled: preset.isEnabled(block),
                onTap: () => onSelected(block),
              ),
            ),
        ],
      ),
    );
  }
}

class _BlockTab extends StatelessWidget {
  const _BlockTab({
    super.key,
    required this.block,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Block block;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? AppTheme.accent
        : enabled
        ? AppTheme.text
        : AppTheme.textDim;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Bloco ${block.label}',
      child: Material(
        color: selected ? AppTheme.accentSoft : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppTheme.accent : AppTheme.stroke,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(blockIcon(block), size: 18, color: foreground),
                const SizedBox(width: 7),
                Text(
                  block.label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                // Ponto discreto quando o bloco esta ligado e nao e a aba atual.
                if (enabled && !selected) ...<Widget>[
                  const SizedBox(width: 6),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
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

class _BlockEditor extends StatelessWidget {
  const _BlockEditor({
    super.key,
    required this.block,
    required this.preset,
    required this.modelNames,
    required this.onChanged,
  });

  final Block block;
  final Preset preset;
  final Map<Block, List<String>> modelNames;
  final ValueChanged<Preset>? onChanged;

  /// Nome do modelo [index], ou `null` quando nao ha nome conhecido.
  ///
  /// AMP e CAB vem do pedal; FX, MOD, DLY e REV vem do catalogo do editor
  /// oficial, porque o pedal nao guarda esses nomes.
  String? _nameOf(int index) {
    final names = modelNames[block];
    if (names != null && index >= 0 && index < names.length) {
      final value = names[index].trim();
      if (value.isNotEmpty) return value;
    }
    return catalogModelName(block, index);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = preset.isEnabled(block);
    // O preset guarda o indice do modelo, 0-based: 0 e o primeiro modelo.
    final selected = preset.model(block);
    final valid = selected >= 0 && selected < block.modelCount
        ? selected
        : null;
    final modelName = _nameOf(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: enabled ? AppTheme.accentSoft : AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                blockIcon(block),
                size: 19,
                color: enabled ? AppTheme.accent : AppTheme.textDim,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    modelName ?? 'Modelo ${selected + 1}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: enabled ? AppTheme.text : AppTheme.textDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${block.label} - modelo ${selected + 1} de '
                    '${block.modelCount}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: enabled
                  ? 'Desligar ${block.label}'
                  : 'Ligar ${block.label}',
              child: Switch(value: enabled, onChanged: _toggle),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Altura fixa: sem ela o DropdownButton estica os itens para ocupar a
        // largura toda e a linha do modelo fica solta no cartao.
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: valid,
              hint: Text('Modelo ${selected + 1}'),
              isExpanded: true,
              isDense: true,
              dropdownColor: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.expand_more, color: AppTheme.textDim),
              padding: EdgeInsets.zero,
              style: const TextStyle(fontSize: 13.5, color: AppTheme.text),
              items: <DropdownMenuItem<int>>[
                for (var i = 0; i < block.modelCount; i++)
                  DropdownMenuItem<int>(
                    value: i,
                    child: Text(
                      _nameOf(i) ?? 'Modelo ${i + 1}',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: i == selected ? AppTheme.accent : AppTheme.text,
                      ),
                    ),
                  ),
              ],
              onChanged: onChanged == null
                  ? null
                  : (int? value) {
                      if (value != null) {
                        onChanged!(preset.withModel(block, value));
                      }
                    },
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: AppTheme.stroke),
        const SizedBox(height: 16),
        _KnobGrid(
          block: block,
          preset: preset,
          enabled: enabled && onChanged != null,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _toggle(bool value) => onChanged?.call(preset.withEnabled(block, value));
}

/// Grade de knobs do modelo atual.
class _KnobGrid extends StatelessWidget {
  const _KnobGrid({
    required this.block,
    required this.preset,
    required this.enabled,
    required this.onChanged,
  });

  final Block block;
  final Preset preset;
  final bool enabled;
  final ValueChanged<Preset>? onChanged;

  @override
  Widget build(BuildContext context) {
    final offsets = Preset.parameterOffsets[block]!;
    final labels = parameterLabelsFor(block, preset.model(block));
    final count = labels.isEmpty ? 1 : labels.length;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Duas colunas em telas estreitas, ate quatro quando ha largura.
        final columns = constraints.maxWidth >= 620
            ? 4
            : constraints.maxWidth >= 430
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            for (var i = 0; i < offsets.length && i < count; i++)
              SizedBox(
                width: width,
                child: _Knob(
                  label: i < labels.length ? labels[i] : 'P${i + 1}',
                  value: preset.parameter(offsets[i]),
                  text: parameterText(block, i, preset.parameter(offsets[i])),
                  enabled: enabled,
                  onChanged: onChanged == null
                      ? null
                      : (int value) =>
                            onChanged!(preset.withParameter(offsets[i], value)),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Um parametro: valor, barra e nome.
class _Knob extends StatelessWidget {
  const _Knob({
    required this.label,
    required this.value,
    required this.text,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;

  /// Valor como o editor oficial mostra (unidade e faixa).
  final String text;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh.withValues(alpha: enabled ? 0.7 : 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.stroke.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? AppTheme.textDim
                        : AppTheme.textDim.withValues(alpha: 0.6),
                  ),
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppTheme.text : AppTheme.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.toDouble().clamp(0, 100),
              max: 100,
              divisions: 100,
              semanticFormatterCallback: (double v) => '$label $v',
              onChanged: enabled && onChanged != null
                  ? (double v) => onChanged!(v.round())
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reordena a cadeia a partir de uma ordem de exibicao.
List<int> reorder(List<int> order, int from, int to) {
  final next = List<int>.of(order);
  if (to > from) to -= 1;
  final moved = next.removeAt(from);
  next.insert(to, moved);
  return next;
}

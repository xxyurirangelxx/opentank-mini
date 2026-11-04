import 'package:flutter/material.dart';

import '../../core/model/preset.dart';
import '../theme.dart';

/// Nomes conhecidos dos modelos, quando verificados contra o pedal.
///
/// Apenas o FX foi confirmado por enumeracao completa (3 modelos, o primeiro e
/// "Noise Gate"). Os demais ficam vazios e a interface mostra o indice.
const Map<Block, List<String>> knownModels = <Block, List<String>>{
  Block.fx: <String>['Noise Gate'],
};

/// Nomes das posicoes de parametro por bloco.
const Map<Block, List<String>> parameterLabels = <Block, List<String>>{
  Block.fx: <String>['Gate'],
  Block.amp: <String>['Gain', 'Presence', 'Master', 'Bass', 'Treble'],
  Block.cab: <String>['Level', 'Low Cut', 'High Cut'],
  Block.mod: <String>['P1', 'P2', 'P3', 'P4', 'P5', 'P6'],
  Block.dly: <String>['P1', 'P2', 'P3', 'P4', 'P5', 'P6'],
  Block.rev: <String>['P1', 'P2', 'P3', 'P4', 'P5', 'P6'],
};

/// Painel de edicao de um bloco: liga/desliga, modelo e parametros.
class BlockPanel extends StatefulWidget {
  const BlockPanel({super.key, required this.preset, required this.onChanged});

  final Preset preset;
  final ValueChanged<Preset>? onChanged;

  @override
  State<BlockPanel> createState() => _BlockPanelState();
}

class _BlockPanelState extends State<BlockPanel> {
  Block _selected = Block.fx;

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final Block block in blockOrder)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(block.label),
                    selected: _selected == block,
                    onSelected: (_) => setState(() => _selected = block),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _BlockEditor(
            block: _selected,
            preset: preset,
            onChanged: widget.onChanged,
          ),
        ),
      ],
    );
  }
}

class _BlockEditor extends StatelessWidget {
  const _BlockEditor({
    required this.block,
    required this.preset,
    required this.onChanged,
  });

  final Block block;
  final Preset preset;
  final ValueChanged<Preset>? onChanged;

  @override
  Widget build(BuildContext context) {
    final names = knownModels[block];
    final enabled = preset.isEnabled(block);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              block.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButton<int>(
                value: preset.model(block),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                dropdownColor: AppTheme.surfaceHigh,
                items: <DropdownMenuItem<int>>[
                  for (var i = 0; i < block.modelCount; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(
                        names != null && i < names.length
                            ? names[i]
                            : 'Modelo ${i + 1}',
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
            Switch(
              value: enabled,
              onChanged: onChanged == null
                  ? null
                  : (bool value) =>
                        onChanged!(preset.withEnabled(block, value)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: <Widget>[
            for (final int offset in Preset.parameterOffsets[block]!)
              _ParameterKnob(
                label: _labelFor(block, offset),
                value: preset.parameter(offset),
                enabled: enabled && onChanged != null,
                onChanged: onChanged == null
                    ? null
                    : (int value) =>
                          onChanged!(preset.withParameter(offset, value)),
              ),
          ],
        ),
      ],
    );
  }

  static String _labelFor(Block block, int offset) {
    final offsets = Preset.parameterOffsets[block]!;
    final index = offsets.indexOf(offset);
    final labels = parameterLabels[block]!;
    if (index >= 0 && index < labels.length) return labels[index];
    return 'P${index + 1}';
  }
}

class _ParameterKnob extends StatelessWidget {
  const _ParameterKnob({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: enabled ? AppTheme.text : AppTheme.textDim,
            ),
          ),
          SizedBox(
            height: 40,
            child: Slider(
              value: value.toDouble(),
              max: 100,
              divisions: 100,
              onChanged: enabled && onChanged != null
                  ? (double v) => onChanged!(v.round())
                  : null,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
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

import 'package:flutter/material.dart';

import '../../core/model/preset.dart';
import '../theme.dart';

/// Visualizacao da cadeia de efeitos, com reordenacao por arraste.
///
/// O routing do pedal e uma sequencia de seis indices de bloco, gravada em
/// `bytes[2..7]`. A ordem exibida e essa mesma sequencia.
class ChainView extends StatelessWidget {
  const ChainView({
    super.key,
    required this.order,
    required this.enabled,
    required this.onChanged,
  });

  /// Indices de bloco na ordem da cadeia.
  final List<int> order;

  /// Estado de cada bloco.
  final Map<Block, bool> enabled;

  /// Chamado com a nova ordem.
  final ValueChanged<List<int>>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorderItem: onChanged == null
            ? (_, _) {}
            : (int oldIndex, int newIndex) {
                final next = List<int>.of(order);
                final moved = next.removeAt(oldIndex);
                next.insert(newIndex, moved);
                onChanged!(next);
              },
        itemBuilder: (BuildContext context, int index) {
          final block = _blockFor(order[index]);
          return ReorderableDragStartListener(
            key: ValueKey<int>(order[index]),
            index: index,
            enabled: onChanged != null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: <Widget>[
                  _ChainNode(block: block, active: enabled[block] ?? false),
                  if (index < order.length - 1)
                    const Icon(
                      Icons.chevron_right,
                      color: AppTheme.textDim,
                      size: 20,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Block _blockFor(int index) {
    const List<Block> byIndex = <Block>[
      Block.fx,
      Block.amp,
      Block.mod,
      Block.dly,
      Block.rev,
      Block.cab,
    ];
    if (index >= 0 && index < byIndex.length) return byIndex[index];
    return Block.fx;
  }
}

class _ChainNode extends StatelessWidget {
  const _ChainNode({required this.block, required this.active});

  final Block block;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accent : AppTheme.textDim;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: active
                ? AppTheme.accentDim.withValues(alpha: 0.35)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? AppTheme.accent : AppTheme.surfaceHigh,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Icon(_iconFor(block), color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          block.label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static IconData _iconFor(Block block) {
    switch (block) {
      case Block.fx:
        return Icons.blur_circular;
      case Block.amp:
        return Icons.more_horiz;
      case Block.cab:
        return Icons.speaker;
      case Block.mod:
        return Icons.circle_outlined;
      case Block.dly:
        return Icons.av_timer;
      case Block.rev:
        return Icons.graphic_eq;
    }
  }
}

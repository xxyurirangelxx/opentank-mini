import 'package:flutter/material.dart';

import '../../core/model/preset.dart';
import '../theme.dart';
import 'block_panel.dart' show blockIcon;

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
    this.onBlockTap,
  });

  /// Indices de bloco na ordem da cadeia.
  final List<int> order;

  /// Estado de cada bloco.
  final Map<Block, bool> enabled;

  /// Chamado com a nova ordem.
  final ValueChanged<List<int>>? onChanged;

  /// Abre o bloco tocado.
  final ValueChanged<Block>? onBlockTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
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
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                children: <Widget>[
                  _ChainNode(
                    block: block,
                    active: enabled[block] ?? false,
                    onTap: onBlockTap == null ? null : () => onBlockTap!(block),
                  ),
                  if (index < order.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 1),
                      child: Icon(
                        Icons.chevron_right,
                        color: AppTheme.stroke,
                        size: 18,
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
  const _ChainNode({required this.block, required this.active, this.onTap});

  final Block block;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accent : AppTheme.textDim;
    return Tooltip(
      message: active ? '${block.label} ligado' : '${block.label} desligado',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.accentDim.withValues(alpha: 0.35)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: active ? AppTheme.accent : AppTheme.stroke,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Icon(blockIcon(block), color: color, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                block.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

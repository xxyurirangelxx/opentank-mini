import 'package:flutter/material.dart';

import '../../core/model/preset.dart';
import '../theme.dart';

/// Seletor de slot com o padrao do pedal (1A..7C).
///
/// Agrupa por banco: os 21 slots do aparelho sao 7 bancos de 3 (A, B, C).
class SlotPicker extends StatelessWidget {
  const SlotPicker({
    super.key,
    required this.selected,
    required this.slots,
    required this.onSelected,
    this.matched = true,
  });

  /// Slot selecionado.
  final int selected;

  /// Conteudo salvo de cada slot.
  final List<Preset> slots;

  final ValueChanged<int>? onSelected;

  /// O preset ativo corresponde ao slot salvo?
  ///
  /// Quando o pedal carrega uma edicao nao salva, o seletor mostra o slot mas
  /// sinaliza que o conteudo atual nao e o salvo.
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.grid_view_rounded,
              size: 14,
              color: AppTheme.textDim,
            ),
            const SizedBox(width: 6),
            const Text(
              'SLOT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppTheme.textDim,
              ),
            ),
            if (!matched) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'editado',
                  style: TextStyle(fontSize: 9.5, color: AppTheme.accent),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: selected,
            isDense: true,
            dropdownColor: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            icon: const Icon(Icons.expand_more, color: AppTheme.textDim),
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            items: <DropdownMenuItem<int>>[
              for (var i = 0; i < slots.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: SizedBox(
                    width: 168,
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 34,
                          child: Text(
                            slotLabel(i),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _summary(slots[i]),
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${slots[i].volume}',
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            onChanged: onSelected == null
                ? null
                : (int? value) {
                    if (value != null) onSelected!(value);
                  },
          ),
        ),
      ],
    );
  }

  /// Resumo curto do slot: quantos blocos estao ligados.
  static String _summary(Preset preset) {
    final count = Block.values.where(preset.isEnabled).length;
    return count == 0 ? 'sem blocos' : '$count blocos';
  }
}

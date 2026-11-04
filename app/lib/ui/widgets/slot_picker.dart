import 'package:flutter/material.dart';

import '../../core/model/preset.dart';
import '../theme.dart';

/// Seletor de slot com o padrao do pedal (1A..7C).
class SlotPicker extends StatelessWidget {
  const SlotPicker({
    super.key,
    required this.selected,
    required this.slots,
    required this.onSelected,
  });

  final int selected;
  final List<Preset> slots;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: selected,
      underline: const SizedBox.shrink(),
      dropdownColor: AppTheme.surfaceHigh,
      style: const TextStyle(color: AppTheme.text, fontSize: 15),
      items: <DropdownMenuItem<int>>[
        for (var i = 0; i < slots.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: SizedBox(
              width: 150,
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 42,
                    child: Text(
                      slotLabel(i),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'vol ${slots[i].volume}',
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 12,
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
    );
  }
}

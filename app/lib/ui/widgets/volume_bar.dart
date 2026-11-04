import 'package:flutter/material.dart';

import '../theme.dart';

/// Barra de volume do preset, com botoes de passo.
class VolumeBar extends StatelessWidget {
  const VolumeBar({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _step(Icons.remove, () => onChanged?.call((value - 1).clamp(0, 100))),
        const SizedBox(width: 12),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            max: 100,
            divisions: 100,
            label: '$value',
            onChanged: onChanged == null
                ? null
                : (double v) => onChanged!.call(v.round()),
          ),
        ),
        const SizedBox(width: 12),
        _step(Icons.add, () => onChanged?.call((value + 1).clamp(0, 100))),
        const SizedBox(width: 16),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _step(IconData icon, VoidCallback action) {
    return IconButton.filledTonal(
      onPressed: onChanged == null ? null : action,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(backgroundColor: AppTheme.surfaceHigh),
    );
  }
}

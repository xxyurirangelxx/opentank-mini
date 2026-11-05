import 'package:flutter/material.dart';

import '../theme.dart';

/// Barra de volume do preset, com botoes de passo.
class VolumeBar extends StatelessWidget {
  const VolumeBar({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.volume_up, size: 17, color: AppTheme.textDim),
              const SizedBox(width: 8),
              const Text(
                'Volume',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDim,
                ),
              ),
              const Spacer(),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              _step(
                Icons.remove,
                () => onChanged?.call((value - 1).clamp(0, 100)),
              ),
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
              _step(
                Icons.add,
                () => onChanged?.call((value + 1).clamp(0, 100)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback action) {
    return IconButton.filledTonal(
      onPressed: onChanged == null ? null : action,
      icon: Icon(icon, size: 18),
      tooltip: icon == Icons.add ? 'Aumentar volume' : 'Diminuir volume',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.surfaceHigh,
        foregroundColor: AppTheme.text,
      ),
    );
  }
}

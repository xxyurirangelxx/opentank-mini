import 'package:flutter/material.dart';

import '../../state/tank_controller.dart';
import '../theme.dart';

/// Selo de conexao da barra superior.
///
/// Mostra o link usado e, quando a conexao cai, deixa o aviso visivel em vez de
/// so mudar a mensagem de texto da tela.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.controller});

  final TankController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final (Color color, String label) = switch (state) {
      TankConnectionState.connected => (AppTheme.success, 'conectado'),
      TankConnectionState.connecting => (AppTheme.accent, 'conectando'),
      TankConnectionState.error => (AppTheme.danger, 'desconectado'),
      TankConnectionState.idle ||
      TankConnectionState.scanning => (AppTheme.textDim, 'inativo'),
    };
    final usb = controller.link == Link.usb;
    return Tooltip(
      message: controller.statusMessage.isEmpty
          ? label
          : controller.statusMessage,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Icon(usb ? Icons.usb : Icons.bluetooth, size: 11, color: color),
            const SizedBox(width: 4),
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
      ),
    );
  }
}

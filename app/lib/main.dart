import 'state/tank_controller.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const OpenTankApp());
}

/// Aplicativo OpenTank Mini.
class OpenTankApp extends StatelessWidget {
  const OpenTankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TankController>(
      create: (_) => TankController(),
      child: MaterialApp(
        title: 'OpenTank Mini',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: const HomeScreen(),
      ),
    );
  }
}

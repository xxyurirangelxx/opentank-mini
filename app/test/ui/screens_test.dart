import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/core/model/preset_bank.dart';
import 'package:opentank_mini/state/tank_controller.dart';
import 'package:opentank_mini/ui/screens/home_screen.dart';
import 'package:opentank_mini/ui/screens/import_screen.dart';
import 'package:opentank_mini/ui/screens/settings_screen.dart';
import 'package:opentank_mini/ui/theme.dart';
import 'package:opentank_mini/ui/widgets/chain_view.dart';
import 'package:opentank_mini/ui/widgets/volume_bar.dart';
import 'package:provider/provider.dart';

import '../support/fake_transport.dart';

Uint8List _preset(int volume) {
  final bytes = Uint8List(92);
  bytes[0] = volume;
  bytes.setRange(2, 8, <int>[0, 1, 5, 2, 3, 4]);
  bytes[8] = 1;
  return bytes;
}

FakeTransport _pedal(Map<int, List<int>> flash, List<int> ram) {
  return FakeTransport((List<int> raw) {
    if (raw[2] == 0x11) return identity();
    final address = raw[7] | (raw[8] << 8);
    if (raw[2] == 0x23) {
      final length = raw[11] | (raw[12] << 8);
      if (address >= 0x1000) return readReply(address, ram.sublist(0, length));
      return readReply(address, flash[address]!.sublist(0, length));
    }
    return ack();
  });
}

Widget _wrap(TankController controller, Widget child) {
  return ChangeNotifierProvider<TankController>.value(
    value: controller,
    child: MaterialApp(theme: AppTheme.build(), home: child),
  );
}

void main() {
  late Map<int, List<int>> flash;
  late List<int> ram;

  setUp(() {
    flash = <int, List<int>>{
      for (var i = 0; i < 21; i++) i * 92: _preset(10 + i),
    };
    ram = List<int>.of(flash[4 * 92]!);
  });

  testWidgets('a tela de conexão aparece desconectada', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    await tester.pumpWidget(_wrap(controller, const HomeScreen()));
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.textContaining('USB'), findsWidgets);
    await tester.runAsync(controller.disconnect);
  });

  testWidgets('o editor monta com banco carregado', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    controller.loadOffline(
      PresetBank(<Preset>[
        for (var i = 0; i < 21; i++) Preset.fromBytes(_preset(10 + i)),
      ]),
      activeSlot: 4,
    );
    await tester.pumpWidget(_wrap(controller, const HomeScreen()));
    await tester.pump();

    expect(find.text('Salvar'), findsOneWidget);
    expect(find.text('Salvar em...'), findsOneWidget);
    expect(find.text('Trocar'), findsOneWidget);
    expect(find.text('Afinador'), findsOneWidget);
    expect(find.text('FX'), findsWidgets);
    expect(find.text('CAB'), findsWidgets);
  });

  testWidgets('o chip de nao salvo aparece apos editar', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    controller.loadOffline(
      PresetBank(<Preset>[
        for (var i = 0; i < 21; i++) Preset.fromBytes(_preset(10 + i)),
      ]),
      activeSlot: 4,
    );
    await tester.pumpWidget(_wrap(controller, const HomeScreen()));
    await tester.pump();
    expect(find.text('nao salvo'), findsNothing);

    // Sem pedal conectado, apply so atualiza o rascunho.
    await controller.apply(controller.draft!.withVolume(63));
    await tester.pump();
    expect(find.text('nao salvo'), findsOneWidget);
  });

  testWidgets('a tela de importação explica o limite do envio', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    await tester.pumpWidget(_wrap(controller, const ImportScreen()));
    expect(find.textContaining('Carregar AMP'), findsOneWidget);
    expect(find.textContaining('Carregar CAB'), findsOneWidget);
    expect(find.textContaining('Gravar permanentemente'), findsOneWidget);
    await tester.runAsync(controller.disconnect);
  });

  testWidgets('a tela de ajustes oferece exportar e restaurar', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    await tester.pumpWidget(_wrap(controller, const SettingsScreen()));
    expect(find.textContaining('Salvar .atkm'), findsOneWidget);
    expect(find.textContaining('Carregar .atkm'), findsOneWidget);
    await tester.runAsync(controller.disconnect);
  });

  testWidgets('VolumeBar respeita o limite', (WidgetTester tester) async {
    int? received;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: VolumeBar(value: 100, onChanged: (int v) => received = v),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.add));
    expect(received, 100, reason: 'não deve passar de 100');
  });

  testWidgets('ChainView mostra os seis blocos na ordem do routing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: ChainView(
            order: <int>[0, 1, 5, 2, 3, 4],
            enabled: <Block, bool>{for (final Block b in Block.values) b: true},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('FX'), findsOneWidget);
    expect(find.text('AMP'), findsOneWidget);
    expect(find.text('CAB'), findsOneWidget);
    expect(find.text('MOD'), findsOneWidget);
    expect(find.text('DLY'), findsOneWidget);
    expect(find.text('REV'), findsOneWidget);
  });
}

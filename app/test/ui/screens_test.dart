import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
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

/// Monta uma tabela de nomes no formato do pedal: 20 registros de 14 bytes.
List<int> _nameTable(List<String> names) {
  final out = <int>[];
  for (var i = 0; i < 20; i++) {
    final value = i < names.length ? names[i] : '';
    final bytes = value.codeUnits.take(14).toList();
    out
      ..addAll(bytes)
      ..addAll(List<int>.filled(14 - bytes.length, 0));
  }
  return out;
}

FakeTransport _pedal(
  Map<int, List<int>> flash,
  List<int> ram, {
  List<String> ampNames = const <String>[],
  List<String> cabNames = const <String>[],
}) {
  return FakeTransport((List<int> raw) {
    if (raw[2] == 0x11) return identity();
    final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
    if (raw[2] == 0x23) {
      final length = raw[11] | (raw[12] << 8);
      if (address == 0x90000000) {
        return readReply(address, _nameTable(ampNames).sublist(0, length));
      }
      if (address == 0x80000000) {
        return readReply(address, _nameTable(cabNames).sublist(0, length));
      }
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

  testWidgets('a tela de conexão móvel oferece apenas Bluetooth', (
    WidgetTester tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final controller = TankController(
        transportFactory: (_) => _pedal(flash, ram),
      );
      await tester.pumpWidget(_wrap(controller, const HomeScreen()));
      expect(find.text('Conectar'), findsOneWidget);
      expect(find.text('Ligue o Bluetooth da Tank Mini'), findsOneWidget);
      expect(
        find.text('Nesta plataforma o app usa apenas Bluetooth.'),
        findsOneWidget,
      );
      expect(find.text('Conecte a Tank Mini por USB'), findsNothing);
      await tester.runAsync(controller.disconnect);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
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

  testWidgets('a lista de modelos mostra o nome que o pedal informa', (
    WidgetTester tester,
  ) async {
    // O preset do teste tem AMP 3 — nas tabelas do pedal, "4RAT_OD".
    ram[15] = 3;
    flash[4 * 92]![15] = 3;
    final controller = TankController(
      transportFactory: (_) => _pedal(
        flash,
        ram,
        ampNames: <String>[
          '1J120_CL',
          '2J900_CL',
          '3VAVE_TS',
          '4RAT_OD',
          '5VAVE_HTS',
        ],
        cabNames: <String>['1AC-SeVin', '2JVM_1960_57', '3MESA_412'],
      ),
    );
    // connect() conversa com o transporte simulado, que entrega a resposta em
    // microtarefa. Dentro de testWidgets o relogio e falso, entao a conversa
    // roda em runAsync; o pump seguinte desenha o estado ja carregado.
    await tester.runAsync(controller.connect);
    await tester.pumpWidget(_wrap(controller, const HomeScreen()));
    await tester.pumpAndSettle();

    // A aba inicial e FX. O pedal nao tem tabela de nomes para ele; o nome vem
    // do catalogo do editor oficial, e o preset traz modelo 0 = "Noise gate".
    // Aparece duas vezes: no cabecalho do painel e no item selecionado da lista.
    expect(find.text('Noise gate'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey<String>('block-tab-AMP')));
    await tester.pumpAndSettle();
    expect(find.text('4RAT_OD'), findsNWidgets(2));

    // Os parametros do AMP sao os do editor oficial, nao P1/P2/P3.
    expect(find.text('Gain'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    expect(find.text('Mid'), findsOneWidget);
    expect(find.text('Presence'), findsNothing);
    await tester.runAsync(controller.disconnect);
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
    expect(find.text('não salvo'), findsNothing);

    // Sem pedal conectado, apply so atualiza o rascunho.
    await controller.apply(controller.draft!.withVolume(63));
    await tester.pump();
    expect(find.text('não salvo'), findsOneWidget);
  });

  testWidgets('a tela de importação explica o limite do envio', (
    WidgetTester tester,
  ) async {
    final controller = TankController(
      transportFactory: (_) => _pedal(flash, ram),
    );
    await tester.pumpWidget(_wrap(controller, const ImportScreen()));
    // Dois cartoes de escolha, com o formato aceito em cada um.
    expect(find.text('AMP'), findsOneWidget);
    expect(find.textContaining('.am2Data'), findsOneWidget);
    expect(find.text('CAB'), findsOneWidget);
    expect(find.textContaining('.wav'), findsOneWidget);
    // O aviso de que a gravacao permanente sobrescreve o slot.
    expect(find.textContaining('sobrescrito'), findsOneWidget);
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

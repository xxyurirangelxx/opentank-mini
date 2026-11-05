import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/device/tank_device.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/core/transport/transport.dart';

import '../support/fake_transport.dart';

/// Transporte que registra a ordem das requisicoes e pode atrasar respostas.
class _Recorder implements TankTransport {
  _Recorder({this.delay = Duration.zero, this.dropFirst = 0});

  final Duration delay;

  /// Quantas respostas de leitura ignorar antes de comecar a responder.
  int dropFirst;

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sent = <List<int>>[];
  int inFlight = 0;
  int maxInFlight = 0;
  List<int> data = List<int>.filled(200, 7);

  @override
  String get name => 'Recorder';

  @override
  Future<void> open() async {}

  @override
  Future<void> send(List<int> raw) async {
    sent.add(List<int>.of(raw));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    if (raw[2] == 0x11) {
      scheduleMicrotask(() {
        inFlight--;
        _incoming.add(identity());
      });
      return;
    }
    final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
    final length = raw[11] | (raw[12] << 8);
    if (dropFirst > 0) {
      dropFirst--;
      scheduleMicrotask(() => inFlight--);
      return;
    }
    scheduleMicrotask(() async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      inFlight--;
      _incoming.add(readReply(address, data.sublist(0, length)));
    });
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    await _incoming.close();
  }
}

void main() {
  group('estabilidade da conversa', () {
    test('requisicoes simultaneas sao serializadas', () async {
      // Duas leituras concorrentes antes disputavam o mesmo `waiter` e a
      // segunda falhava com "requisicao anterior em andamento". Agora entram
      // numa fila e as duas completam, uma depois da outra.
      final transport = _Recorder(delay: const Duration(milliseconds: 30));
      final device = TankDevice(transport);
      await device.connect();

      final results = await Future.wait(<Future<List<int>>>[
        device.readBytes(0, 92),
        device.readBytes(92, 92),
        device.readBytes(184, 16),
      ]);
      expect(results.map((List<int> r) => r.length), <int>[92, 92, 16]);
      expect(transport.maxInFlight, 1, reason: 'nunca duas em voo');
      await device.disconnect();
    });

    test('resposta perdida e repetida e o pedido conclui', () async {
      // O BLE perde notificacao com frequencia; repetir resolve sem erro.
      final transport = _Recorder(dropFirst: 1);
      final device = TankDevice(
        transport,
        readTimeout: const Duration(milliseconds: 120),
      );
      await device.connect();
      final data = await device.readBytes(0, 92);
      expect(data.length, 92);
      expect(transport.sent.length, greaterThan(2), reason: 'houve repeticao');
      await device.disconnect();
    });

    test('desistir so depois de esgotar as tentativas', () async {
      final transport = _Recorder(dropFirst: 99);
      final device = TankDevice(
        transport,
        readTimeout: const Duration(milliseconds: 60),
        maxAttempts: 2,
      );
      await device.connect();
      await expectLater(
        device.readBytes(0, 92),
        throwsA(isA<TransportException>()),
      );
      await device.disconnect();
    });

    test(
      'queda do link interrompe a espera em vez de estourar o tempo',
      () async {
        final transport = _Recorder(dropFirst: 1);
        final device = TankDevice(
          transport,
          readTimeout: const Duration(seconds: 5),
        );
        await device.connect();
        final pending = device.readBytes(0, 92);
        device.markLost('BLE caiu');
        final watch = Stopwatch()..start();
        await expectLater(pending, throwsA(isA<TransportException>()));
        watch.stop();
        expect(
          watch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'nao deve esperar o timeout inteiro',
        );
        await device.disconnect();
      },
    );

    test('a sessao avisa quando o link cai', () async {
      final device = TankDevice(_Recorder());
      await device.connect();
      final lost = Completer<void>();
      device.lost.listen((_) => lost.complete());
      device.markLost('cabo removido');
      await lost.future.timeout(const Duration(seconds: 1));
      expect(device.isOpen, isFalse);
      await device.disconnect();
    });
  });

  group('preset ativo', () {
    test('le o preset mesmo com a fila ocupada', () async {
      final transport = _Recorder(delay: const Duration(milliseconds: 20));
      final device = TankDevice(transport);
      await device.connect();
      final a = device.readActive();
      final b = device.readActive();
      final values = await Future.wait(<Future<Preset>>[a, b]);
      expect(values[0].bytes, values[1].bytes);
      expect(transport.maxInFlight, 1);
      await device.disconnect();
    });
  });
}

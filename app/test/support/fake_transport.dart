import 'dart:async';

import 'package:opentank_mini/core/transport/transport.dart';

/// Transporte simulado: responde como o pedal, sem hardware.
///
/// Reproduz as respostas reais observadas nas capturas, incluindo o ACK
/// generico, o ACK negativo e o formato do dump de leitura.
class FakeTransport implements TankTransport {
  FakeTransport(this.handler);

  /// Recebe o frame SysEx e devolve a resposta crua (sem F0/F7), ou `null`.
  final List<int>? Function(List<int> raw) handler;

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sent = <List<int>>[];
  bool opened = false;
  bool closed = false;

  @override
  String get name => 'Fake';

  @override
  Future<void> open() async {
    opened = true;
  }

  @override
  Future<void> send(List<int> raw) async {
    sent.add(List<int>.of(raw));
    final reply = handler(raw);
    if (reply == null) return;
    // Entrega assincrona, como o MIDI real.
    scheduleMicrotask(() => _incoming.add(reply));
  }

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}

/// Resposta de leitura sintetica.
List<int> readReply(int address, List<int> payload) {
  final packet = <int>[
    0x00,
    0x59,
    0x23,
    (payload.length + 8) & 0xFF,
    (payload.length + 8) >> 8,
    0x00,
    0x04,
    address & 0xFF,
    (address >> 8) & 0xFF,
    (address >> 16) & 0xFF,
    (address >> 24) & 0xFF,
    payload.length & 0xFF,
    payload.length >> 8,
    0x00,
    ...payload,
    0x00,
  ];
  var sum = 0;
  for (var i = 5; i < packet.length - 1; i++) {
    sum += packet[i];
  }
  packet[packet.length - 1] = (255 - sum) % 256;
  return packet;
}

/// ACK generico.
List<int> ack() => <int>[0x00, 0x59, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF];

/// ACK negativo.
List<int> nak() => <int>[0x00, 0x59, 0x00, 0x01, 0x00, 0x00, 0x01, 0xFE];

/// Resposta de identificacao.
List<int> identity([String name = 'TANK MINI']) {
  final body = <int>[...name.codeUnits, 0x00, 0x09];
  final packet = <int>[
    0x00,
    0x59,
    0x11,
    (body.length + 8) & 0xFF,
    (body.length + 8) >> 8,
    0x00,
    0x00,
    ...body,
    0x00,
  ];
  var sum = 0;
  for (var i = 5; i < packet.length - 1; i++) {
    sum += packet[i];
  }
  packet[packet.length - 1] = (255 - sum) % 256;
  return packet;
}

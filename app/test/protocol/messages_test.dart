import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/protocol/messages.dart';

/// Cada vetor abaixo saiu de uma captura real do editor oficial ou foi
/// validado contra o dispositivo.
void main() {
  group('checksum', () {
    test('cobre do indice 5', () {
      final raw = _hex('00 59 11 00 00 00 FF');
      expect(checksum(raw), 0xFF);
    });

    test('sobrevive a payload acima de 247 bytes', () {
      final payload = List<int>.generate(1015, (i) => (i * 13 + 5) % 256);
      final packet = writeRequest(0, payload, area: Area.model);
      final raw = packet.sublist(0, packet.length - 1);
      var sum = 0;
      for (var i = 5; i < raw.length; i++) {
        sum += raw[i];
      }
      expect((255 - sum) % 256, packet.last);
    });
  });

  group('requisicoes', () {
    test('identificacao', () {
      expect(_hex6(identifyRequest()), '00 59 11 00 00 00 FF');
    });

    test('leitura da RAM', () {
      expect(
        _hex6(readRequest(ramAddress, presetSize)),
        '00 59 23 08 00 00 04 00 00 00 10 5C 00 00 8F',
      );
    });

    test('leitura do slot 4', () {
      expect(
        _hex6(readRequest(4 * presetSize, presetSize)),
        '00 59 23 08 00 00 04 70 01 00 00 5C 00 00 2E',
      );
    });

    test('commit', () {
      expect(
        _hex6(commitRequest()),
        '00 59 22 08 00 00 04 00 00 00 F0 00 00 00 0B',
      );
    });

    test('selecao de slot', () {
      expect(
        _hex6(selectRequest(4)),
        '00 59 22 09 00 00 04 04 00 00 E0 01 00 00 01 15',
      );
    });

    test('toggle de AMP', () {
      expect(
        _hex6(toggleRequest(BlockAddress.ampToggle, 1)),
        '00 59 22 09 00 00 04 09 00 00 10 01 00 00 01 E0',
      );
    });

    test('knob de volume', () {
      expect(
        _hex6(knobRequest(0x00, 99)),
        '00 59 22 0A 00 00 04 00 00 00 10 02 00 00 63 00 86',
      );
    });

    test('routing', () {
      expect(
        _hex6(routingRequest([1, 0, 5, 2, 3, 4])),
        '00 59 22 0E 00 00 04 02 00 00 10 06 00 00 01 00 05 02 03 04 D4',
      );
    });

    test('bypass', () {
      expect(
        _hex6(bypassRequest(true)),
        '00 59 22 09 00 00 04 02 00 00 20 01 00 00 01 D7',
      );
    });

    test('loopback', () {
      expect(
        _hex6(loopbackRequest(true)),
        '00 59 22 09 00 00 04 00 00 00 D0 01 00 00 01 29',
      );
    });

    test('afinador', () {
      expect(
        _hex6(tunerRequest(true)),
        '00 59 22 09 00 00 04 02 00 10 70 01 00 00 01 77',
      );
    });

    test('consulta de estado global', () {
      expect(
        _hex6(globalStateRequest()),
        '00 59 23 08 00 00 04 00 00 00 20 04 00 00 D7',
      );
    });

    test('consulta do afinador', () {
      expect(
        _hex6(tunerStateRequest()),
        '00 59 23 08 00 00 04 00 00 10 70 06 00 00 75',
      );
    });

    test('preview de modelo', () {
      expect(
        _hex6(previewModelRequest(kind: 1)),
        '00 59 22 09 00 00 05 00 00 00 A0 01 00 00 01 58',
      );
      expect(
        _hex6(previewModelRequest(kind: 2)),
        '00 59 22 09 00 00 05 00 00 00 A0 01 00 00 02 57',
      );
    });

    test('escrita de preset bate com o save capturado', () {
      final payload = List<int>.generate(92, (i) => i);
      final packet = writeRequest(4 * presetSize, payload);
      expect(
        _hex6(packet.sublist(0, 14)),
        '00 59 22 64 00 00 04 70 01 00 00 5C 00 00',
      );
      expect(packet.length, 107);
      expect(packet.sublist(14, 106), payload);
    });
  });

  test('routing exige seis bytes', () {
    expect(() => routingRequest([0, 1]), throwsArgumentError);
  });
}

Uint8List _hex(String value) => Uint8List.fromList(
  value.split(' ').map((b) => int.parse(b, radix: 16)).toList(),
);

String _hex6(List<int> data) => data
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

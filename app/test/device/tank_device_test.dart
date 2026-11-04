import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/device/tank_device.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/core/protocol/messages.dart';

import '../support/fake_transport.dart';

/// Preset de exemplo com os valores verificados no aparelho.
Uint8List samplePreset({int volume = 100}) {
  final bytes = Uint8List(92);
  bytes[0] = volume;
  bytes.setRange(2, 8, <int>[0, 1, 5, 2, 3, 4]);
  bytes[8] = 1;
  bytes[13] = 1;
  bytes[15] = 4;
  return bytes;
}

void main() {
  group('TankDevice', () {
    test('conecta e le a identificacao', () async {
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        return ack();
      });
      final device = TankDevice(transport);
      expect(await device.connect(), 'TANK MINI');
      expect(transport.opened, isTrue);
      await device.disconnect();
      expect(transport.closed, isTrue);
    });

    test('le um slot inteiro', () async {
      final preset = samplePreset();
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) {
          final address = raw[7] | (raw[8] << 8);
          final length = raw[11] | (raw[12] << 8);
          return readReply(address, preset.sublist(0, length));
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      final slot = await device.readSlot(4);
      expect(slot.volume, 100);
      expect(slot.routing, <int>[0, 1, 5, 2, 3, 4]);
      await device.disconnect();
    });

    test('readBlock fatia em pedacos de no maximo 431 bytes', () async {
      final buffer = List<int>.generate(900, (i) => i % 256);
      final lengths = <int>[];
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) {
          final length = raw[11] | (raw[12] << 8);
          lengths.add(length);
          return readReply(0, buffer.sublist(0, length));
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      final data = await device.readBlock(0, 900);
      expect(data.length, 900);
      expect(lengths, <int>[431, 431, 38]);
      await device.disconnect();
    });

    test('leitura rejeita tamanho acima do limite', () async {
      final device = TankDevice(FakeTransport((_) => ack()));
      await device.connect();
      expect(() => device.readBytes(0, 500), throwsArgumentError);
      await device.disconnect();
    });

    test('endereco invalido vira ReadException', () async {
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        return nak();
      });
      final device = TankDevice(transport);
      await device.connect();
      await expectLater(
        device.readBytes(0x7FFFFFFF, 92),
        throwsA(isA<ReadException>()),
      );
      await device.disconnect();
    });

    test('saveSlot envia escrita e commit', () async {
      final packets = <List<int>>[];
      final transport = FakeTransport((List<int> raw) {
        packets.add(raw);
        if (raw[2] == 0x11) return identity();
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      packets.clear();
      await device.saveSlot(4, Preset.fromBytes(samplePreset()));
      expect(packets.length, 2);
      expect(packets[0][2], 0x22);
      // area do preset fica no indice 6; o commit tem 0xF0 no indice 10
      expect(packets[0][6], 0x04);
      expect(packets[1][10], 0xF0);
      await device.disconnect();
    });

    test('escrita rejeitada lanca WriteException', () async {
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        return nak();
      });
      final device = TankDevice(transport);
      await device.connect();
      await expectLater(
        device.saveSlot(0, Preset.fromBytes(samplePreset())),
        throwsA(isA<WriteException>()),
      );
      await device.disconnect();
    });

    test('swap troca os dois slots', () async {
      final first = samplePreset(volume: 10);
      final second = samplePreset(volume: 20);
      final storage = <int, List<int>>{0: first, 92: second};
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) {
          final address = raw[7] | (raw[8] << 8);
          final length = raw[11] | (raw[12] << 8);
          return readReply(address, storage[address]!.sublist(0, length));
        }
        if (raw[2] == 0x22 && raw[10] != 0xF0) {
          final address = raw[7] | (raw[8] << 8);
          final length = raw[11] | (raw[12] << 8);
          storage[address] = raw.sublist(14, 14 + length);
          return ack();
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      await device.swapSlots(0, 1);
      expect(storage[0]![0], 20);
      expect(storage[92]![0], 10);
      await device.disconnect();
    });

    test('selectSlot exige convergencia', () async {
      final preset = samplePreset();
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) return readReply(ramAddress, preset);
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      final reads = await device.selectSlot(
        4,
        expected: Preset.fromBytes(preset),
      );
      expect(reads, 1);
      await device.disconnect();
    });

    test('selectSlot falha se nao convergir', () async {
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) {
          return readReply(ramAddress, samplePreset(volume: 5));
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      await expectLater(
        device.selectSlot(
          4,
          expected: Preset.fromBytes(samplePreset(volume: 99)),
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await device.disconnect();
    });

    test('uploadModel fatia em 1015 bytes e ativa o preview', () async {
      final packets = <List<int>>[];
      final transport = FakeTransport((List<int> raw) {
        packets.add(raw);
        if (raw[2] == 0x11) return identity();
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      packets.clear();
      final buffer = Uint8List(8192);
      buffer.setRange(0, 4, <int>[0x41, 0x4D, 0x32, 0x00]);
      await device.uploadModel(buffer, previewKind: 1);
      final writes = packets.where((List<int> p) {
        if (p[2] != 0x22 || p[6] != 0x05) return false;
        final length = p[11] | (p[12] << 8);
        return length > 1;
      });
      expect(writes.length, 9);
      final preview = packets.last;
      expect(preview[14], 0x01);
      await device.disconnect();
    });

    test('uploadModel com CAB usa preview 2', () async {
      final packets = <List<int>>[];
      final transport = FakeTransport((List<int> raw) {
        packets.add(raw);
        if (raw[2] == 0x11) return identity();
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      packets.clear();
      await device.uploadModel(Uint8List(6164), previewKind: 2);
      expect(packets.last[14], 0x02);
      await device.disconnect();
    });

    test('operacoes exigem conexao', () async {
      final device = TankDevice(FakeTransport((_) => ack()));
      await expectLater(device.readSlot(0), throwsStateError);
    });

    test('writeModelFlash apaga, escreve e relê sem commit', () async {
      final packets = <List<int>>[];
      final stored = <int, int>{};
      final transport = FakeTransport((List<int> raw) {
        packets.add(raw);
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x21) {
          final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
          stored.removeWhere((int k, int v) => k >= address && k < address + 4096);
          return ack();
        }
        if (raw[2] == 0x22 && (raw[11] | (raw[12] << 8)) > 1) {
          final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
          final length = raw[11] | (raw[12] << 8);
          for (var i = 0; i < length; i++) {
            stored[address + i] = raw[14 + i];
          }
        }
        if (raw[2] == 0x23) {
          final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
          final length = raw[11] | (raw[12] << 8);
          return readReply(
            address,
            <int>[for (var i = 0; i < length; i++) stored[address + i] ?? 0],
          );
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      packets.clear();

      final record = List<int>.generate(8192, (int i) => (i * 3) & 0xFF);
      await device.writeModelFlash(0x70000000 + 5 * 8192, record);

      final erases = packets
          .where((List<int> p) => p[2] == 0x21)
          .map(
            (List<int> p) =>
                p[7] | (p[8] << 8) | (p[9] << 16) | (p[10] << 24),
          )
          .toList();
      expect(erases, <int>[
        0x70000000 + 5 * 8192,
        0x70000000 + 5 * 8192 + 4096,
      ]);
      // O editor oficial nao envia commit no restore de modelos; enviar um
      // commit com area 0x05 faz o pedal descartar a gravacao.
      final commits = packets.where(
        (List<int> p) => p.length > 10 && p[10] == 0xF0,
      );
      expect(commits, isEmpty, reason: 'modelo nao leva commit');
      expect(
        <int>[
          for (var i = 0; i < 8192; i++)
            stored[0x70000000 + 5 * 8192 + i] ?? -1,
        ],
        record,
      );
      await device.disconnect();
    });

    test('writeModelFlash falha quando a releitura nao confere', () async {
      var reads = 0;
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x23) {
          reads++;
          final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
          final length = raw[11] | (raw[12] << 8);
          return readReply(address, List<int>.filled(length, 0xFF));
        }
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      final record = List<int>.filled(8192, 0x11);
      await expectLater(
        device.writeModelFlash(0x70000000, record),
        throwsA(isA<FlashWriteException>()),
      );
      expect(reads, greaterThan(0));
      await device.disconnect();
    });

    test('writeModelFlash propaga NAK do apagamento', () async {
      final transport = FakeTransport((List<int> raw) {
        if (raw[2] == 0x11) return identity();
        if (raw[2] == 0x21) return nak();
        return ack();
      });
      final device = TankDevice(transport);
      await device.connect();
      await expectLater(
        device.writeModelFlash(0x70000000, List<int>.filled(4096, 0)),
        throwsA(isA<WriteException>()),
      );
      await device.disconnect();
    });
  });
}

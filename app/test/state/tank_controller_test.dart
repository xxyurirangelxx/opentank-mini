import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/model/model_flash.dart';
import 'package:opentank_mini/core/model/model_format.dart';
import 'package:opentank_mini/core/model/preset.dart';
import 'package:opentank_mini/state/tank_controller.dart';

import '../support/fake_transport.dart';

Uint8List _preset(int volume, int ampModel) {
  final bytes = Uint8List(92);
  bytes[0] = volume;
  bytes.setRange(2, 8, <int>[0, 1, 5, 2, 3, 4]);
  bytes[9] = 1;
  bytes[15] = ampModel;
  bytes[32] = 50;
  return bytes;
}

/// Emula o pedal: flash por endereco, RAM do preset ativo e NAK fora da faixa.
FakeTransport _pedal(Map<int, List<int>> flash, List<int> ram) {
  return FakeTransport((List<int> raw) {
    if (raw[2] == 0x11) return identity();
    final address = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
    if (raw[2] == 0x23) {
      final length = raw[11] | (raw[12] << 8);
      if (address >= 0x10000000) {
        return readReply(address, ram.sublist(0, length));
      }
      final data = flash[address];
      if (data == null) return nak();
      return readReply(address, data.sublist(0, length));
    }
    if (raw[2] == 0x22) {
      // O tipo do comando esta no tamanho declarado (raw[3:5]), nao nos dados.
      final commandLength = raw[3] | (raw[4] << 8);
      if (raw[10] == 0xF0) return ack(); // commit
      if (commandLength == 0x09) {
        // toggle, ou selecao de slot (discriminada pelo tipo 0xE0)
        final kind = raw[10];
        if (kind == 0xE0) {
          // A selecao leva o slot no indice 7 (o endereco), nao nos dados.
          final slot = raw[7];
          final data = flash[slot * 92];
          if (data != null) ram.setRange(0, 92, data);
          return ack();
        }
        ram[raw[7] & 0xFF] = raw[14];
        return ack();
      }
      if (commandLength == 0x0A) {
        final offset = raw[7] & 0xFF;
        ram[offset] = raw[14];
        ram[offset + 1] = raw[15];
        return ack();
      }
      if (commandLength == 0x0E) {
        ram.setRange(2, 8, raw.sublist(14, 20));
        return ack();
      }
      final length = raw[11] | (raw[12] << 8);
      flash[address] = raw.sublist(14, 14 + length);
      return ack();
    }
    return ack();
  });
}

void main() {
  late Map<int, List<int>> flash;
  late List<int> ram;

  setUp(() {
    flash = <int, List<int>>{
      for (var i = 0; i < 21; i++) i * 92: _preset(10 + i, i % 20),
    };
    ram = List<int>.of(flash[4 * 92]!);
  });

  TankController build() =>
      TankController(transportFactory: (_) => _pedal(flash, ram));

  test('conecta, le o banco e identifica o slot ativo', () async {
    final controller = build();
    await controller.connect();
    expect(controller.connected, isTrue);
    expect(controller.bank!.slots.length, 21);
    expect(controller.activeSlot, 4);
    expect(controller.draft!.volume, 14);
    expect(controller.isDirty, isFalse);
    await controller.disconnect();
  });

  test('editar aplica no pedal e marca como nao salvo', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(controller.draft!.withVolume(77));
    expect(controller.draft!.volume, 77);
    expect(ram[0], 77, reason: 'o volume deve chegar na RAM do pedal');
    expect(controller.isDirty, isTrue);
    expect(
      controller.bank!.slots[4].volume,
      14,
      reason: 'a flash nao muda sem Save',
    );
    await controller.disconnect();
  });

  test('save grava no slot e limpa a marca de alterado', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(controller.draft!.withVolume(33));
    await controller.save();
    expect(flash[4 * 92]![0], 33);
    expect(controller.isDirty, isFalse);
    expect(controller.bank!.slots[4].volume, 33);
    await controller.disconnect();
  });

  test('saveTo grava em outro slot sem mudar o ativo', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(controller.draft!.withVolume(42));
    await controller.saveTo(10);
    expect(flash[10 * 92]![0], 42);
    expect(controller.activeSlot, 4);
    expect(flash[4 * 92]![0], 14, reason: 'o slot ativo nao foi gravado');
    await controller.disconnect();
  });

  test('revert descarta o rascunho', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(controller.draft!.withVolume(90));
    expect(controller.isDirty, isTrue);
    await controller.revert();
    expect(controller.draft!.volume, 14);
    expect(controller.isDirty, isFalse);
    await controller.disconnect();
  });

  test('trocar modelo aplica no pedal', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(controller.draft!.withModel(Block.amp, 9));
    expect(ram[15], 9);
    expect(controller.draft!.model(Block.amp), 9);
    await controller.disconnect();
  });

  test('routing aplica no pedal', () async {
    final controller = build();
    await controller.connect();
    await controller.apply(
      controller.draft!.withRouting(<int>[5, 4, 3, 2, 1, 0]),
    );
    expect(ram.sublist(2, 8), <int>[5, 4, 3, 2, 1, 0]);
    await controller.disconnect();
  });

  test('selectSlot troca o preset ativo', () async {
    final controller = build();
    await controller.connect();
    await controller.selectSlot(7);
    expect(controller.activeSlot, 7);
    expect(controller.draft!.volume, 17);
    await controller.disconnect();
  });

  test('swap troca dois slots no banco e na flash', () async {
    final controller = build();
    await controller.connect();
    final before4 = controller.bank!.slots[4];
    final before9 = List<int>.of(flash[9 * 92]!);
    await controller.swap(4, 9);
    expect(flash[4 * 92], before9);
    expect(controller.bank!.slots[9], before4);
    await controller.disconnect();
  });

  test('restoreBank grava e confere os 21 slots', () async {
    final controller = build();
    await controller.connect();
    final bank = controller.bank!;
    final changed = <Preset>[
      for (var i = 0; i < 21; i++) bank.slots[i].withVolume(i),
    ];
    await controller.restoreBank(
      bank.withSlot(0, changed[0]).withSlot(20, changed[20]),
    );
    expect(flash[0]![0], 0);
    expect(flash[20 * 92]![0], 20);
    await controller.disconnect();
  });

  test('erro na conexao vira estado de erro', () async {
    final controller = TankController(
      transportFactory: (_) => FakeTransport((_) => null),
    );
    await controller.connect();
    expect(controller.state, TankConnectionState.error);
    expect(controller.statusMessage, contains('Falha ao conectar'));
    await controller.disconnect();
  });

  test('rajada de edicoes envia apenas o estado final', () async {
    final controller = build();
    await controller.connect();
    // Simula arrastar o slider: muitas chamadas sem esperar.
    final futures = <Future<void>>[];
    for (var v = 20; v <= 60; v += 10) {
      futures.add(controller.apply(controller.draft!.withVolume(v)));
    }
    await Future.wait(futures);
    expect(ram[0], 60, reason: 'o pedal deve terminar no valor final');
    expect(controller.draft!.volume, 60);
    await controller.disconnect();
  });

  test('setLink so funciona desconectado', () async {
    final controller = build();
    controller.setLink(Link.bluetooth);
    expect(controller.link, Link.bluetooth);
    await controller.connect();
    controller.setLink(Link.usb);
    expect(
      controller.link,
      Link.bluetooth,
      reason: 'nao deve trocar conectado',
    );
    await controller.disconnect();
  });

  test('saveModel grava o registro na flash de modelos', () async {
    final modelFlash = <int, int>{};
    final transport = FakeTransport((List<int> raw) {
      if (raw[2] == 0x11) return identity();
      if (raw[2] == 0x21) {
        final address =
            raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
        for (var i = 0; i < 4096; i++) {
          modelFlash.remove(address + i);
        }
        return ack();
      }
      final address =
          raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24);
      if (raw[2] == 0x22) {
        final length = raw[11] | (raw[12] << 8);
        for (var i = 0; i < length; i++) {
          modelFlash[address + i] = raw[14 + i];
        }
        return ack();
      }
      if (raw[2] == 0x23) {
        final length = raw[11] | (raw[12] << 8);
        return readReply(address, <int>[
          for (var i = 0; i < length; i++) modelFlash[address + i] ?? 0,
        ]);
      }
      return ack();
    });
    final controller = TankController(transportFactory: (_) => transport);
    await controller.connect();

    final buffer = Uint8List(modelBufferSize)..setRange(0, 4, ampMagic);
    for (var i = 18; i < 8192; i++) {
      buffer[i] = (i * 5) & 0xFF;
    }
    await controller.saveModel(
      kind: ModelKind.amp,
      index: 7,
      name: 'TEST_AMP',
      buffer: buffer,
    );

    final address = modelFlashAddress(isCab: false, index: 7);
    final record = <int>[
      for (var i = 0; i < 8192; i++) modelFlash[address + i] ?? -1,
    ];
    expect(record.sublist(0, 4), factoryAmpMagic);
    expect(decodeFlashName(record), 'TEST_AMP');
    expect(record.sublist(18), buffer.sublist(18));
    await controller.disconnect();
  });
}

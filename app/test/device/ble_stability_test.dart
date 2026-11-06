import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:opentank_mini/core/device/tank_device.dart';
import 'package:opentank_mini/platform/ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

import '../support/fake_transport.dart';

class _BlePlatform extends UniversalBlePlatform {
  int reads = 0;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {
    updateScanResult(
      BleDevice(deviceId: 'aa:bb:cc:dd:ee:ff', name: 'TANK MINI'),
    );
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async => <BleService>[BleService(BleTransport.serviceUuid, [])];

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => 185;

  @override
  Future<void> setNotifiable(
    String deviceId,
    String service,
    String characteristic,
    BleInputProperty bleInputProperty,
  ) async {}

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    final List<int> reply;
    if (value[2] == 0x11) {
      reply = identity()..[3] = identity().length - 7;
    } else {
      reads++;
      final full = readReply(0, List<int>.filled(92, 7));
      if (reads == 1) {
        scheduleMicrotask(() {
          updateCharacteristicValue(
            deviceId,
            BleTransport.rxUuid,
            Uint8List.fromList(full.sublist(0, 20)),
            null,
          );
          updateCharacteristicValue(
            deviceId,
            BleTransport.rxUuid,
            Uint8List.fromList(full.sublist(20)),
            null,
          );
        });
        return;
      }
      reply = reads == 2 ? full.sublist(0, 20) : full;
    }
    scheduleMicrotask(
      () => updateCharacteristicValue(
        deviceId,
        BleTransport.rxUuid,
        Uint8List.fromList(reply),
        null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('repeticao recupera leitura apos notificacao incompleta', () async {
    UniversalBle.setInstance(_BlePlatform());
    final device = TankDevice(
      BleTransport(deviceName: 'TANK MINI'),
      readTimeout: const Duration(milliseconds: 100),
    );
    await device.connect();
    try {
      expect(await device.readBytes(0, 92), List<int>.filled(92, 7));
      expect(await device.readBytes(0, 92), List<int>.filled(92, 7));
    } finally {
      await device.disconnect();
    }
  });
}

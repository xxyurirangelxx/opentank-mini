"""Descoberta BLE e consultas não destrutivas de identidade e RAM."""
import asyncio
import json
from pathlib import Path
import time
from bleak import BleakScanner, BleakClient

ROOT = Path(__file__).resolve().parent
TX = '0000ae41-0000-1000-8000-00805f9b34fb'
RX = '0000ae42-0000-1000-8000-00805f9b34fb'
SERVICE = '0000ae40-0000-1000-8000-00805f9b34fb'
report = {'results': [], 'notifications': []}

def record(test, status, **details):
    entry = dict(test=test, status=status, **details)
    report['results'].append(entry)
    print(json.dumps(entry, ensure_ascii=False), flush=True)

async def main():
    devices = await BleakScanner.discover(timeout=12, return_adv=True)
    candidates = [(d, a) for d, a in devices.values()
                  if 'TANK' in (d.name or a.local_name or '').upper()
                  or SERVICE in a.service_uuids]
    record('descoberta', 'PASS' if candidates else 'BLOCKED', candidates=[dict(name=d.name, address=d.address, services=a.service_uuids) for d,a in candidates])
    if len(candidates) != 1:
        return
    async with BleakClient(candidates[0][0], timeout=15) as client:
        report['services'] = [dict(uuid=s.uuid, characteristics=[dict(uuid=c.uuid, properties=c.properties) for c in s.characteristics]) for s in client.services]
        assert client.services.get_characteristic(TX) and client.services.get_characteristic(RX)
        record('GATT', 'PASS', mtu=client.mtu_size)
        buffer = bytearray()
        packets = []
        def notified(sender, data):
            report['notifications'].append(dict(time=time.time(), hex=bytes(data).hex(' ')))
            buffer.extend(data)
            while len(buffer) >= 6:
                if buffer[:2] != b'\x00\x59':
                    raise ValueError('Cabeçalho BLE inesperado')
                length = buffer[3] + 7
                if len(buffer) < length:
                    break
                packet = bytes(buffer[:length])
                del buffer[:length]
                packets.append(packet)
        await client.start_notify(RX, notified)
        for name, request, command in [('identificação', '00 59 11 00 00 00 ff', 0x11), ('RAM', '00 59 23 08 00 00 04 00 00 00 10 5c 00 00 8f', 0x23)]:
            start = len(packets)
            await client.write_gatt_char(TX, bytes.fromhex(request), response=False)
            deadline = time.monotonic()+5
            found = None
            while time.monotonic() < deadline:
                found = next((p for p in packets[start:] if p[2] == command), None)
                if found:
                    break
                await asyncio.sleep(0.05)
            if found is None:
                record(name, 'FAIL', reason='timeout', buffered=buffer.hex(' '))
                continue
            assert sum(found[4:]) % 256 == 255
            if name == 'RAM':
                assert len(found) == 107
                assert found[14:-1] == (ROOT/'snapshot-active-ram.tkm').read_bytes()
            record(name, 'PASS', raw=found.hex(' '))
        async def exchange(raw, command):
            packet = bytearray(raw)
            packet[-1] = (255 - sum(packet[4:-1])) % 256
            start = len(packets)
            await client.write_gatt_char(TX, packet, response=False)
            deadline = time.monotonic()+3
            while time.monotonic() < deadline:
                for response in packets[start:]:
                    if response[2] == command:
                        assert sum(response[4:]) % 256 == 255
                        return response
                await asyncio.sleep(0.02)
            raise TimeoutError('Sem resposta BLE ao comando '+str(command))
        async def read_ram():
            response = await exchange(bytes.fromhex('00 59 23 08 00 00 04 00 00 00 10 5c 00 00 8f'), 0x23)
            assert len(response) == 107
            return response[14:-1]
        async def change(address, value, subcommand):
            raw = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 10 01 00 00 00 00')
            raw[7], raw[14], raw[11] = address, value, subcommand
            if subcommand == 2:
                raw[3] = 10
                raw.insert(-1, 0)
            await exchange(raw, 0)
        async def select(index):
            raw = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 e0 01 00 00 01 00')
            raw[7] = index
            await exchange(raw, 0)
            expected = slots[index]
            deadline = time.monotonic() + 3
            attempts = 0
            while time.monotonic() < deadline:
                attempts += 1
                if await read_ram() == expected:
                    record('convergência '+str(index), 'PASS', reads=attempts)
                    return
                await asyncio.sleep(0.05)
            raise TimeoutError('Preset não convergiu: '+str(index))
        before = await read_ram()
        backup = (ROOT/'Tank Mini_AllPresets.atkm').read_bytes()
        slots = [backup[i*92:(i+1)*92] for i in range(21)]
        origin = slots.index(before)
        for name, address in [('FX',8), ('AMP',9), ('MOD',10), ('DLY',11), ('REV',12), ('CAB',13)]:
            try:
                await change(address, 1-before[address], 1)
                actual = await read_ram()
                expected = bytearray(before)
                expected[address] = 1-before[address]
                assert actual == expected
                record('toggle '+name, 'PASS')
            finally:
                await change(address, before[address], 1)
                assert await read_ram() == before
        addresses = [base+2*i for base,count in [(20,4),(32,5),(44,6),(56,6),(68,6),(80,3)] for i in range(count)]
        for address in addresses:
            original = before[address]
            temporary = original-1 if original else 1
            try:
                await change(address, temporary, 2)
                actual = await read_ram()
                expected = bytearray(before)
                expected[address] = temporary
                assert actual == expected
                record('knob '+str(address), 'PASS')
            finally:
                await change(address, original, 2)
                assert await read_ram() == before
        for name, address, count in [('FX',14,3),('AMP',15,20),('MOD',16,7),('DLY',17,5),('REV',18,6),('CAB',19,20)]:
            expected_model = (before[address]+1) % count
            try:
                await change(address, expected_model, 1)
                actual = await read_ram()
                assert actual[address] == expected_model
                record('modelo '+name, 'PASS', differences=[i for i in range(92) if actual[i] != before[i]])
            finally:
                await select((origin+1) % 21)
                await select(origin)
                assert await read_ram() == before
        try:
            await change(32, before[32]-1 if before[32] else 1, 2)
            assert await read_ram() != before
            await select((origin+1) % 21)
            await select(origin)
            assert await read_ram() == before
            record('preview descartado ao trocar preset', 'PASS')
        finally:
            await select(origin)
            assert await read_ram() == before
        try:
            for index, expected in enumerate(slots):
                await select(index)
                assert await read_ram() == expected
                record('select '+str(index//3+1)+'ABC'[index%3], 'PASS')
        finally:
            await select(origin)
            assert await read_ram() == before
            record('restauração final', 'PASS')
        await client.stop_notify(RX)

try:
    asyncio.run(main())
except Exception as exc:
    record('execução BLE', 'FAIL', error=repr(exc))
finally:
    (ROOT/('validation-ble-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')

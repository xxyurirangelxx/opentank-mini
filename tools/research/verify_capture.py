"""Verifica capturas localmente com decoder independente; não acessa hardware."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
for mode in ('identity', 'ram'):
    document = json.loads((root / f'probe_{mode}_result.json').read_text(encoding='utf-8'))
    for event in document['events']:
        frame = bytes.fromhex(event['hex'])
        assert frame[0] == 0xf0 and frame[-1] == 0xf7
        accumulator = bits = 0
        raw = bytearray()
        for value in frame[1:-1]:
            assert value < 128
            accumulator |= value << bits
            bits += 7
            while bits >= 8:
                raw.append(accumulator & 255)
                accumulator >>= 8
                bits -= 8
        expected = raw[3] + 7
        packet = raw[:expected]
        assert len(packet) == expected
        assert not any(raw[expected:])
        assert (sum(packet[4:]) & 255) == 255
        print(mode, 'bytes:', len(packet), 'checksum válido')
        if mode == 'identity':
            print('Identificação:', packet[6:-1].rstrip(b'\x00').decode('ascii'))
        else:
            assert packet[:14] == bytes.fromhex('00 59 23 64 00 00 04 00 00 00 10 5c 00 00')
            payload = packet[14:-1]
            assert len(payload) == 92
            target = root / 'snapshot-active-ram.tkm'
            if target.exists():
                assert target.read_bytes() == payload, 'Snapshot existente diferente; não sobrescrever.'
            else:
                target.write_bytes(payload)
            print('Snapshot RAM:', len(payload), 'bytes; SHA-256:', hashlib.sha256(payload).hexdigest())

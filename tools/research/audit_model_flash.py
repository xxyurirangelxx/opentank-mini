"""Auditoria: compara os 30 blocos da flash de modelos com o backup de fabrica.

Cada leitura valida o endereco ecoado na resposta. Somente leitura.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, SCOPE, Tank, read_request  # noqa: E402

REF = ROOT.parent.parent / 'research' / 'dumps' / 'factory-am4-buffer.bin'
BLOCK = 8192
CHUNK = 431


def read_checked(tank, address, length, timeout=2.0):
    start = len(tank.events)
    tank.send(read_request(address, length, AREA_AMP), settle=0.0)
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for event in tank.events[start:]:
            if event['kind'] != 'IN | SYSEX':
                continue
            raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
            if raw[:3] != bytes.fromhex('00 59 23'):
                continue
            echoed = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24)
            size = raw[11] | (raw[12] << 8)
            if echoed != address or size != length:
                continue
            return raw[14:-1]
        time.sleep(0.01)
    raise TimeoutError(f'sem resposta para {address:#x}')


def read_block(tank, address, length):
    out = b''
    while len(out) < length:
        n = min(CHUNK, length - len(out))
        out += read_checked(tank, address + len(out), n)
    return out


ref = REF.read_bytes()
with Tank() as tank:
    bad = []
    for index in range(30):
        address = 0x70000000 + index * BLOCK
        live = read_block(tank, address, BLOCK)
        expected = ref[index * BLOCK:(index + 1) * BLOCK]
        if live == expected:
            print(f'{index:2d} ok    {live[4:18]!r}', flush=True)
        else:
            zeros = sum(1 for b in live if b == 0)
            diff = sum(1 for a, b in zip(live, expected) if a != b)
            bad.append(index)
            print(f'{index:2d} DIFERE diff={diff} zeros={zeros} '
                  f'magic={live[:4]!r} nome={live[4:18]!r}', flush=True)
    print('blocos com problema:', bad)

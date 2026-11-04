"""Lê a região de modelos em 0x70000000 (245760 B) e compara com o buffer capturado.

Somente leitura. Serve para (a) confirmar que a região é endereçável byte a byte e
(b) guardar um backup exato da flash de modelos de fábrica.
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, Tank, read_request  # noqa: E402

SIZE = 245760
CHUNK = 431
OUT = ROOT.parent.parent / 'research' / 'dumps' / 'models-70000000.bin'
CAPTURED = ROOT.parent.parent / 'research' / 'dumps' / 'factory-am4-buffer.bin'


def read_fast(tank, address, length):
    """Leitura com settle curto: o pedal responde em ~10 ms."""
    frame = read_request(address, length, AREA_AMP)
    tank.send(frame, settle=0.02)
    return tank.wait_response(bytes.fromhex('00 59 23'), timeout=1.5,
                              start=len(tank.events) - 1)[14:-1]


with Tank() as tank:
    data = bytearray()
    while len(data) < SIZE:
        chunk = read_fast(tank, 0x70000000 + len(data), CHUNK)
        data += chunk
        if len(data) % (CHUNK * 100) < CHUNK:
            print('lidos', len(data), flush=True)
print('total', len(data))
OUT.write_bytes(bytes(data))
print('sha256', hashlib.sha256(bytes(data)).hexdigest())
if CAPTURED.exists():
    cap = CAPTURED.read_bytes()
    print('capturado', len(cap), hashlib.sha256(cap).hexdigest())
    print('iguais:', bytes(data) == cap[:len(data)])
    if bytes(data) != cap[:len(data)]:
        for i in range(0, min(len(data), len(cap))):
            if data[i] != cap[i]:
                print('primeira diferenca no offset', i)
                break

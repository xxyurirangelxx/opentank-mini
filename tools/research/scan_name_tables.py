"""Procura tabelas de nomes de FX/MOD/DLY/REV perto das tabelas conhecidas.

Somente leitura. Varre paginas de 4 KiB nas regioes 0x80000000..0x90100000 e
0xA0000000, imprimindo qualquer pagina com texto ASCII imprimivel relevante.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import Tank, AREA_AMP  # noqa: E402


def printable(blob):
    out = bytearray()
    for byte in blob:
        out.append(byte if 0x20 <= byte <= 0x7E else 0x2E)
    return out.decode('ascii')


with Tank() as tank:
    addresses = []
    for base in (0x80000000, 0x90000000):
        addresses += [base + k * 0x1000 for k in range(0, 10)]
    addresses += [0xA0000000 + k * 0x1000 for k in range(0, 4)]
    for address in addresses:
        chunk = tank.read(address, 431, AREA_AMP)
        if chunk is None:
            print(f'{address:08X}: invalido')
            continue
        text = printable(chunk).rstrip('.')
        print(f'{address:08X}: {text[:100]!r}')

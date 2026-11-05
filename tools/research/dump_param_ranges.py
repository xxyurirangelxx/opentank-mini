"""Faixa real dos parametros nos 21 slots de fabrica.

Imprime os pares uint16 de CAB (80..85) e AMP (32..42) de cada slot, com o
modelo correspondente, para descobrir se o campo guarda 0..100 ou a unidade
exibida pelo editor (Hz, ms, %).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import Tank  # noqa: E402


def u16(data, offset):
    return data[offset] | (data[offset + 1] << 8)


with Tank() as tank:
    print('slot | FX MOD DLY REV CAB | AMP modelo | AMP params 32..41 | CAB 80..85')
    for slot in range(21):
        data = tank.read(slot * 92, 92)
        amp_model = data[15]
        amp = [u16(data, o) for o in range(32, 42, 2)]
        cab = [u16(data, o) for o in range(80, 86, 2)]
        models = list(data[14:20])
        print(f'{slot:2d} | {models} | {amp_model:2d} | {amp} | {cab}')

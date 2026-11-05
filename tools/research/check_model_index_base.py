"""Mostra os indices de modelo do preset ativo e a que nome cada um leva.

Serve para decidir se o preset guarda indice 0-based ou 1-based — e, com isso,
qual rotulo a lista suspensa deve mostrar em cada posicao.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, Tank  # noqa: E402

with Tank() as tank:
    active = tank.dump()
    print('bytes 8..19:', ' '.join(f'{b:02x}' for b in active[8:20]))
    print('ligados FX..CAB:', list(active[8:14]))
    print('modelos FX..CAB:', list(active[14:20]))
    amp = tank.read(0x90000000, 280, AREA_AMP)
    cab = tank.read(0x80000000, 280, AREA_AMP)
    names = {
        'amp': [amp[i:i + 14].split(b'\0')[0].decode('ascii', 'replace')
                for i in range(0, 280, 14)],
        'cab': [cab[i:i + 14].split(b'\0')[0].decode('ascii', 'replace')
                for i in range(0, 280, 14)],
    }
    for label, value in (('AMP', active[15]), ('CAB', active[19])):
        table = names[label.lower()]
        one_based = table[value - 1] if 1 <= value <= 20 else '(sem nome)'
        zero_based = table[value] if 0 <= value < 20 else '(fora)'
        print(f'{label} {value}: 1-based -> {one_based!r} | '
              f'0-based -> {zero_based!r}')

"""O que muda em 0x20000000 e em 0x10000000 ao editar pelo protocolo?

Se a RAM (`0x10000000`) acompanhar uma edicao feita por comando, ela serve para
o app seguir o que o usuario faz no pedal fisico. A regiao `0x20000000` e a que
o M-EFCS consulta a cada 1 segundo; aqui se descobre o que ela carrega.

Toda alteracao e desfeita no final.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_PRESETS, Tank  # noqa: E402

RAM = 0x10000000
GLOBAL = 0x20000000


def snapshot(tank):
    return (tank.read(RAM, 92), tank.read(GLOBAL, 64))


def show(label, ram, glob):
    print(f'{label}')
    print(f'  RAM    : {ram.hex(" ")}')
    print(f'  GLOBAL : {glob.hex(" ")}')


with Tank() as tank:
    original_ram = tank.dump()
    base_ram, base_glob = snapshot(tank)
    show('estado inicial', base_ram, base_glob)

    # 1) Volume: comando 0x0A no offset 0.
    tank.knob(0, 37)
    time.sleep(0.3)
    ram, glob = snapshot(tank)
    print(f'\napos volume=37: RAM[0]={ram[0]} (antes {base_ram[0]})')
    print(f'  global mudou: {glob != base_glob}')

    # 2) Modelo de AMP: comando 0x09 no offset 15.
    tank.toggle(15, 3)
    time.sleep(0.3)
    ram2, glob2 = snapshot(tank)
    print(f'\napos AMP modelo=3: RAM[15]={ram2[15]} global mudou: {glob2 != base_glob}')

    # 3) Parametro de AMP (offset 32).
    tank.knob(32, 21)
    time.sleep(0.3)
    ram3, glob3 = snapshot(tank)
    print(f'\napos AMP param32=21: RAM[32]={ram3[32]} global mudou: {glob3 != base_glob}')

    # 4) Consulta de estado do afinador (0x70100000), a outra que o editor faz.
    tuner = tank.read(0x70100000, 6)
    print(f'\nafinador 0x70100000: {tuner.hex(" ") if tuner else None}')

    print('\nrestaurando...')
    tank.select(int(sys.argv[1]) if len(sys.argv) > 1 else 4)
    time.sleep(0.5)
    back = tank.dump()
    print('RAM voltou ao original:', back == original_ram)

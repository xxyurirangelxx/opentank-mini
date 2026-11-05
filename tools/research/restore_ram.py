"""Repoe a RAM com o conteudo do slot salvo, sem gravar na flash.

Usado para desfazer escritas de sonda. Le o slot da flash e escreve os mesmos
92 bytes na RAM do preset ativo: nada e salvo, so o estado vivo volta ao que o
preset tem guardado.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_PRESETS, Tank  # noqa: E402

RAM = 0x10000000
slot = int(sys.argv[1]) if len(sys.argv) > 1 else 4

with Tank() as tank:
    saved = tank.read(slot * 92, 92)
    print(f'slot {slot} na flash:', saved.hex(' '))
    current = tank.dump()
    print('RAM antes          :', current.hex(' '))
    if current == saved:
        print('RAM ja corresponde ao slot; nada a fazer')
        raise SystemExit(0)

    reply = tank.write(RAM, saved, AREA_PRESETS)
    print('escrita:', reply.hex(' ') if reply else 'sem resposta')
    time.sleep(0.4)
    back = tank.dump()
    diff = [i for i in range(92) if back[i] != saved[i]]
    print('RAM depois         :', back.hex(' '))
    print('confere:', back == saved, '| diferencas:', diff)
    # O pedal normaliza alguns parametros ao aplicar na RAM; relatar e seguir.

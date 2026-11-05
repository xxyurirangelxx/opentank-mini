"""Qual número seleciona qual modelo? Prova com o buffer de prévia.

Seleciona um AMP e lê o buffer de modelo (`area 0x05`, endereço 0): se o
firmware carregar o modelo escolhido ali, o nome no cabeçalho diz qual modelo
foi realmente selecionado. Restaura o modelo original no fim (RAM, sem gravar).
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, Tank  # noqa: E402

with Tank() as tank:
    original = tank.dump()
    start_model = original[15]
    print('AMP atual na RAM:', start_model, flush=True)

    before = tank.read(0, 18, AREA_AMP)
    print('buffer antes:', before[:18], flush=True)

    for value in (5, 1):
        tank.toggle(15, value)
        buffer = tank.read(0, 18, AREA_AMP)
        name = buffer[4:18].split(b'\0')[0].decode('ascii', 'replace')
        ram = tank.dump()
        print(f'selecionado {value}: RAM byte 15 = {ram[15]}, '
              f'buffer = {buffer[:4]!r} nome = {name!r}', flush=True)

    tank.toggle(15, start_model)
    back = tank.dump()
    print('restaurado:', back == original, flush=True)

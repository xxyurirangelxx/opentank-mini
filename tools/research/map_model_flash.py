"""Confirma o mapa entre o buffer de modelo (area 05, addr 0) e a flash de modelos.

Lê o preset ativo, o buffer de modelo e o bloco de flash correspondente ao índice
de AMP do preset. Somente leitura.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, AREA_PRESETS, RAM_ADDRESS, Tank, read_request  # noqa: E402

MODEL_FLASH = 0x70000000
BLOCK = 8192


def read_fast(tank, address, length, area=AREA_AMP):
    start = len(tank.events)
    tank.send(read_request(address, length, area), settle=0.02)
    return tank.wait_response(bytes.fromhex('00 59 23'), timeout=1.5,
                              start=start)[14:-1]


with Tank() as tank:
    active = read_fast(tank, RAM_ADDRESS, 92, AREA_PRESETS)
    print('preset ativo:', active.hex(' '))
    amp_index = active[15]
    cab_index = active[19]
    print('modelo AMP do preset:', amp_index, '| CAB:', cab_index)

    buffer = b''
    while len(buffer) < BLOCK:
        buffer += read_fast(tank, len(buffer), 431)
    print('buffer RAM magic:', buffer[:4])

    for kind, index, base in (('AMP', amp_index, 0), ('CAB', cab_index, 20)):
        # O indice do preset e 1-based; blocos 0..19 = AMP, 20..29 = CAB
        block_index = (index - 1) if kind == 'AMP' else (20 + (index - 1) // 2)
        addr = MODEL_FLASH + block_index * BLOCK
        flash = b''
        while len(flash) < BLOCK:
            flash += read_fast(tank, addr + len(flash), 431)
        print(f'{kind} indice {index}: bloco {block_index} em {addr:#x} magic {flash[:4]}')

    # comparar com todos os blocos para achar o que casa com o buffer
    hits = []
    for i in range(30):
        addr = MODEL_FLASH + i * BLOCK
        flash = b''
        while len(flash) < BLOCK:
            flash += read_fast(tank, addr + len(flash), 431)
        body_f, body_b = flash[18:], buffer[18:]
        if body_f == body_b:
            hits.append((i, 'identico'))
        elif flash[4:18] == buffer[4:18]:
            hits.append((i, 'cabecalho igual'))
        if i in (amp_index - 1, 20 + (cab_index - 1) // 2):
            from pathlib import Path as P
            (P('research/dumps') / f'block-{i}.bin').write_bytes(flash)
    print('blocos que casam com o buffer:', hits)

"""Dump cru das tabelas de nomes, sem interpretar (somente leitura).

Grava research/dumps/name-tables.bin com os bytes exatos devolvidos pelo pedal
em 0x80000000 (CAB) e 0x90000000 (AMP), para que o decodificador do app seja
escrito contra o formato real e nao contra suposicoes.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import Tank, AREA_AMP  # noqa: E402

OUT = ROOT.parent.parent / 'research' / 'dumps'

with Tank() as tank:
    for base, label in ((0x90000000, 'AMP'), (0x80000000, 'CAB')):
        for offset in (0, 431):
            chunk = tank.read(base + offset, 431, AREA_AMP)
            if chunk is None:
                print(f'{label} @ {base + offset:08X}: endereco invalido')
                continue
            (OUT / f'names-{label.lower()}-{offset}.bin').write_bytes(chunk)
            print(f'{label} @ {base + offset:08X}: {len(chunk)} bytes')
            print('  ' + ' '.join(f'{b:02x}' for b in chunk[:240]))
            text = chunk.split(b'\0')
            print('  campos:', [t.decode('ascii', 'replace') for t in text[:24]])

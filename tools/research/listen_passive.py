"""Escuta passiva: o pedal avisa sozinho quando algo muda?

Abre a porta e nao envia nada por N segundos. Se nada chegar, nao existe
notificacao espontanea (nem de troca de preset, nem de knob) e o app precisa
consultar a RAM por conta propria.

Uso: python listen_passive.py [segundos]
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import SCOPE, Tank  # noqa: E402

seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 15.0

with Tank() as tank:
    start = len(tank.events)
    print(f'escutando {seconds:.0f}s sem enviar nada...', flush=True)
    time.sleep(seconds)
    arrivals = [e for e in tank.events[start:] if e['kind'] == 'IN | SYSEX']
    print(f'mensagens espontaneas: {len(arrivals)}')
    for event in arrivals[:20]:
        raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
        print('  ', raw.hex(' '))

"""O pedal envia heartbeat? Testa com a sessao identificada.

A primeira versao escutou sem conversar antes e nao viu nada. Agora identifica,
consulta o estado e depois fica em silencio, imprimindo toda mensagem que
chegar com o instante em que chegou — para medir o intervalo do heartbeat.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import GLOBAL_REQUEST, RAM_REQUEST, SCOPE, Tank  # noqa: E402

IDENTIFY = bytes.fromhex('00 59 11 00 00 00 00')

with Tank() as tank:
    print('identificando...', flush=True)
    tank.send(IDENTIFY, settle=0.3)
    tank.send(RAM_REQUEST, settle=0.4)
    tank.send(GLOBAL_REQUEST, settle=0.4)

    start = len(tank.events)
    t0 = time.monotonic()
    print('escutando 20s em silencio...', flush=True)
    time.sleep(20)
    arrivals = [e for e in tank.events[start:] if e['kind'] == 'IN | SYSEX']
    print(f'mensagens espontaneas: {len(arrivals)}')
    previous = None
    for event in arrivals[:40]:
        raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
        delta = '' if previous is None else f' (+{event["time"] - previous:.3f}s)'
        previous = event['time']
        print(f'  t={event["time"] - t0:6.2f}s{delta} {raw.hex(" ")}')

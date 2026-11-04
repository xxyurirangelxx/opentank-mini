"""Valida escrita de flash em um slot sacrificial, com restauracao verificada."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from tankbase import Tank, backup_slots, AREA_PRESETS

slots = backup_slots()
TARGET = 20          # slot 7C, restaurado ao final
original = slots[TARGET]
address = TARGET * 92

# perfil de teste: copia do slot 0 com o volume alterado
probe = bytearray(slots[0])
probe[0] = (probe[0] + 1) % 101

report = []
def record(**values):
    report.append(values)
    print(values, flush=True)

with Tank() as t:
    before = t.read(address)
    assert before == original, 'Slot alvo divergente do backup'
    record(step='leitura inicial', ok=True)

    # 1) escrita + commit
    ack = t.write(address, bytes(probe))
    record(step='ACK escrita', ack=ack.hex(' ') if ack else 'SEM ACK')
    t.commit()
    time.sleep(0.4)

    after = t.read(address)
    record(step='leitura apos escrita', igual_probe=after == bytes(probe))

    # 2) o preset aparece igual em RAM ao selecionar?
    t.select(TARGET)
    ram = t.dump()
    record(step='RAM apos select', igual_probe=ram == bytes(probe))

    # 3) restore exato e verificacao
    t.select_confirm(4, slots[4])
    ack2 = t.write(address, original)
    record(step='ACK restore', ack=ack2.hex(' ') if ack2 else 'SEM ACK')
    t.commit()
    time.sleep(0.4)
    restored = t.read(address)
    record(step='restaurado', igual_backup=restored == original)

print('RESUMO:', all(v.get('ok', True) and v.get('igual_probe', True) and
                      v.get('igual_backup', True) for v in report))

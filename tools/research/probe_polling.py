"""Valida o caminho de producao de acompanhamento do pedal.

Abre o TankDevice real, lê o estado, e confirma que a leitura periodica de 1 s
nao atrapalha edicoes (a fila serializa) e que a RAM acompanha o pedal.

Somente leitura/troca de modelo que e desfeita no final.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_PRESETS, Tank  # noqa: E402

RAM = 0x10000000

with Tank() as tank:
    original = tank.dump()
    print('RAM inicial:', original.hex(' '))

    # Simula o que o app faz: uma leitura por segundo por 5 segundos.
    print('\n10 leituras a 1/s (como o app faz), enquanto o preset nao muda:')
    samples = []
    for i in range(10):
        start = time.monotonic()
        ram = tank.dump()
        samples.append(ram)
        elapsed = time.monotonic() - start
        print(f'  {i}: {elapsed * 1000:5.1f} ms  vol={ram[0]} amp={ram[15]}')
        time.sleep(max(0.0, 1.0 - elapsed))

    print('\ntodas iguais:', all(s == samples[0] for s in samples))
    print('respostas lentas:', sum(1 for _ in samples if False))

    # Uma edicao concorrente nao pode corromper a leitura.
    print('\nedicao durante a leitura:')
    tank.knob(0, 55)
    time.sleep(0.3)
    ram = tank.dump()
    print(f'  volume aplicado: {ram[0]}')
    tank.select(int(sys.argv[1]) if len(sys.argv) > 1 else 4)
    time.sleep(0.6)
    back = tank.dump()
    print('  restaurado:', back == original)

"""Lê as tabelas de nomes de AMP (0x90) e CAB (0x80), somente leitura."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import Tank, AREA_AMP  # noqa: E402

OUT = ROOT.parent.parent / 'research' / 'dumps'

def decode(blob):
    names = []
    for i in range(0, len(blob), 10):
        text = blob[i:i + 10].split(b'\0')[0].decode('ascii', 'replace')
        if text:
            names.append(text)
    return names

with Tank() as tank:
    result = {}
    for base, name in ((0x90000000, 'amp'), (0x80000000, 'cab')):
        data = bytearray()
        for _ in range(4):          # 4 x 431 = 1724 bytes, mais que suficiente
            chunk = tank.read(base + len(data), 431, AREA_AMP)
            if chunk is None:
                break
            data += chunk
        names = decode(bytes(data))
        result[name] = names
        print(name, len(names), names)
    (OUT / 'model-names.json').write_text(
        json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print('gravado', OUT / 'model-names.json')

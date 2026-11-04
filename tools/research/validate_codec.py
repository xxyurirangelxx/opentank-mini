"""Testes offline do codec herdado contra implementação independente."""
import importlib.util
import json
from pathlib import Path
import random

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('probe', root/'probe_readonly.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
scope = probe.load_scope()

def reference_encode(raw):
    value = int.from_bytes(raw, 'little')
    count = (len(raw)*8+6)//7
    return bytes([0xf0]+[(value >> (7*i)) & 127 for i in range(count)]+[0xf7])

def reference_decode(frame, length):
    value = sum(b << (7*i) for i,b in enumerate(frame[1:-1]))
    return (value & ((1 << (length*8))-1)).to_bytes(length, 'little')

rng = random.Random(42)
results = []
for size in (7,8,15,16,17,34,92,107,256,512):
    exact = roundtrip = independent = 0
    for index in range(100):
        raw = bytes(rng.randrange(256) for _ in range(size))
        frame = scope['encode_sysex'](raw)
        decoded = scope['decode_sysex'](frame)
        exact += frame == reference_encode(raw)
        roundtrip += decoded == raw
        independent += reference_decode(frame, size) == raw
    results.append(dict(size=size, total=100, canonical_encoder=exact, exact_legacy_roundtrip=roundtrip, independent_payload=independent))
print(json.dumps(results, indent=2))
(root/'validation-codec.json').write_text(json.dumps(results, indent=2), encoding='utf-8')

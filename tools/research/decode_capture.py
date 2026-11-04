"""Decodifica captura WinMM local e agrupa comandos TX únicos."""
import importlib.util
import json
from pathlib import Path
import sys
root = Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('probe',root/'probe_readonly.py')
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
scope=probe.load_scope()
path=Path(sys.argv[1]) if len(sys.argv)>1 else max(root.glob('capture-mefcs-*.jsonl'),key=lambda p:p.name)
unique={}
for line in path.read_text(encoding='utf-8').splitlines():
    event=json.loads(line)
    if event.get('payload',{}).get('kind')!='TX SYSEX' or 'hex' not in event:
        continue
    raw=scope['decode_sysex'](bytes.fromhex(event['hex']))
    key=raw.hex(' ')
    entry=unique.setdefault(key,dict(raw=key,count=0,first=event['payload']['time'],last=0))
    entry['count']+=1
    entry['last']=event['payload']['time']
print('CAPTURA',path.name)
for value in unique.values():
    if len(value['raw']) > 450:
        raw=bytes.fromhex(value['raw'])
        import hashlib
        value=dict(value,raw=value['raw'][:150]+' ...',length=len(raw),sha256=hashlib.sha256(raw).hexdigest())
    print(json.dumps(value))

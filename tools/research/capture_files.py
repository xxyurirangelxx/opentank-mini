"""Observa aberturas de arquivo do editor (somente leitura; não altera retornos)."""
import argparse
import json
from pathlib import Path
import time
import frida

ROOT = Path(__file__).resolve().parent
LOG = ROOT / ('capture-files-' + time.strftime('%Y%m%d-%H%M%S') + '.jsonl')
SCRIPT = r'''
const hooked = new Set();
function hook(name, address) {
  if (address === null || address.isNull() || hooked.has(address.toString())) return;
  hooked.add(address.toString());
  send({kind:'HOOK',name:name});
  Interceptor.attach(address, {onEnter(args) {
    try {
      if (name === 'CreateFileW') {
        const p = args[0].readUtf16String();
        if (p) send({kind:'OPEN',time:Date.now(),path:p});
      }
    } catch(e) {}
  }});
}
for (const mod of ['kernel32.dll','KernelBase.dll']) {
  for (const name of ['CreateFileW','CreateFile2']) {
    hook(name, Module.findExportByName(mod, name));
  }
}
send({kind:'READY'});
'''

def message(value, data):
    entry = dict(value)
    if data:
        entry['hex'] = data.hex(' ')
    with LOG.open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(entry, ensure_ascii=False) + '\n')

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, default=120)
args = parser.parse_args()
pid = int((ROOT / 'capture-mefcs-pid.txt').read_text())
local = frida.get_local_device()
print('PID:', pid, 'LOG:', LOG, flush=True)
session = local.attach(pid)
script = session.create_script(SCRIPT)
script.on('message', message)
script.load()
try:
    time.sleep(args.seconds)
finally:
    session.detach()
    print('Captura de arquivos encerrada.', flush=True)

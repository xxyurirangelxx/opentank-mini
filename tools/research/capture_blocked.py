"""Captura comandos MIDI do editor SEM deixá-los chegar ao pedal.

Serve para descobrir comandos destrutivos (reset de fábrica) sem executá-los.
`midiOutLongMsg` é interceptado e devolvido com sucesso sem chamar o original:
o editor acredita ter enviado, o pedal não recebe nada.
"""
import argparse
import json
import sys
from pathlib import Path
import time
import frida

ROOT = Path(__file__).resolve().parent
LOG = ROOT / ('capture-blocked-' + time.strftime('%Y%m%d-%H%M%S') + '.jsonl')
SCRIPT = r'''
const hooked = new Set();
function hook(name, address) {
  if (address === null || address.isNull() || hooked.has(address.toString())) return;
  hooked.add(address.toString());
  send({kind:'HOOK', name:name});
  Interceptor.attach(address, {
    onEnter(args) {
      try {
        const hdr = args[1];
        const len = hdr.add(Process.pointerSize).readU32();
        const data = hdr.readPointer().readByteArray(len);
        send({kind:'BLOCKED TX', time:Date.now()}, data);
        // Marca o cabecalho como concluido e devolve sucesso: o editor segue,
        // o pedal nunca ve a mensagem.
        hdr.add(Process.pointerSize * 2 + 4).writeU32(1); // dwFlags |= MHDR_DONE
      } catch (e) { send({kind:'ERROR', message:String(e)}); }
    },
    onLeave(retval) { retval.replace(0); }
  });
}
Process.attachModuleObserver({onAdded(module) {
  const lower = module.name.toLowerCase();
  if (lower === 'winmm.dll' || lower === 'winmmbase.dll') {
    hook('midiOutLongMsg', module.findExportByName('midiOutLongMsg'));
  }
}});
'''

def message(value, data):
    entry = dict(value)
    if data:
        entry['hex'] = data.hex(' ')
    with LOG.open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(entry, ensure_ascii=False) + '\n')
    print(json.dumps({k: v for k, v in entry.items() if k != 'hex'}), flush=True)

parser = argparse.ArgumentParser()
parser.add_argument('--seconds', type=int, default=240)
args = parser.parse_args()
pid = int(Path(sys.argv[0]).parent.joinpath('mefcs-pid.txt').read_text())
local = frida.get_local_device()
print('PID:', pid, 'LOG:', LOG, flush=True)
print('AVISO: nenhuma mensagem sera entregue ao pedal.', flush=True)
session = local.attach(pid)
script = session.create_script(SCRIPT)
script.on('message', message)
script.load()
try:
    time.sleep(args.seconds)
finally:
    session.detach()
    print('Captura encerrada.', flush=True)

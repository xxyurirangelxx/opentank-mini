"""Captura local de APIs MIDI do editor oficial; não modifica argumentos ou retornos."""
import argparse
import json
from pathlib import Path
import time
import frida

ROOT = Path(__file__).resolve().parent
APP = ROOT/'capture-input'/'m-efcs'/'m_efcs.exe'
LOG = ROOT/('capture-mefcs-'+time.strftime('%Y%m%d-%H%M%S')+'.jsonl')
SCRIPT = r'''
const hooked = new Set();
function bytes(header, received) {
  const size = header.add(received ? Process.pointerSize+4 : Process.pointerSize).readU32();
  if (size > 0 && size <= 65536) return header.readPointer().readByteArray(size);
  return null;
}
function hook(name, address) {
  if (address === null || address.isNull() || hooked.has(address.toString())) return;
  hooked.add(address.toString());
  send({kind:'HOOK',name:name,address:address.toString()});
  Interceptor.attach(address, {onEnter(args) {
    try {
      if (name === 'midiOutLongMsg') send({kind:'TX SYSEX',time:Date.now()},bytes(args[1],false));
      if (name === 'midiInAddBuffer') {
        const data=bytes(args[1],true);
        if (data !== null) send({kind:'RX SYSEX REQUEUE',time:Date.now()},data);
      }
      if (name === 'midiOutShortMsg') send({kind:'TX SHORT',time:Date.now(),value:args[1].toUInt32()});
      if (name === 'midiInOpen') {
        send({kind:'OPEN IN',flags:args[4].toUInt32()});
        if ((args[4].toUInt32() & 0x00070000) === 0x00030000) {
          const callback=args[2], key='cb'+callback.toString();
          if (!hooked.has(key)) {
            hooked.add(key);
            Interceptor.attach(callback,{onEnter(input) {
              try {
                if (input[1].toUInt32() === 0x3c4) send({kind:'RX SYSEX',time:Date.now()},bytes(input[3],true));
              } catch(e) {send({kind:'ERROR',message:String(e)});}
            }});
          }
        }
      }
    } catch(e) {send({kind:'ERROR',message:String(e)});}
  }});
}
Process.attachModuleObserver({onAdded(module) {
  const lower=module.name.toLowerCase();
  if (lower.includes('midi') || lower.includes('winmm')) send({kind:'MODULE',name:module.name,path:module.path});
  if (lower === 'winmm.dll' || lower === 'winmmbase.dll') {
    for (const name of ['midiOutLongMsg','midiOutShortMsg','midiInOpen','midiInAddBuffer']) hook(name,module.findExportByName(name));
  }
}});
const getProc=Module.findExportByName('kernel32.dll','GetProcAddress');
Interceptor.attach(getProc,{
  onEnter(args) {
    this.name=null;
    try {if (args[1].toUInt32()>65535) this.name=args[1].readCString();} catch(e) {}
  },
  onLeave(result) {
    if (this.name && this.name.startsWith('midi')) {
      send({kind:'RESOLVE',name:this.name,address:result.toString()});
      if (['midiOutLongMsg','midiOutShortMsg','midiInOpen','midiInAddBuffer'].includes(this.name)) hook(this.name,result);
    }
  }
});
'''

def message(value, data):
    entry = dict(value)
    if data:
        entry['hex'] = data.hex(' ')
    with LOG.open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(entry, ensure_ascii=False)+'\n')
    print(json.dumps(entry, ensure_ascii=False), flush=True)

parser = argparse.ArgumentParser()
parser.add_argument('--attach', action='store_true')
args = parser.parse_args()
local = frida.get_local_device()
if args.attach:
    pid = int((ROOT/'capture-mefcs-pid.txt').read_text())
else:
    pid = local.spawn([str(APP)], cwd=str(ROOT))
    (ROOT/'capture-mefcs-pid.txt').write_text(str(pid), encoding='ascii')
print('PID:',pid,'LOG:',LOG,flush=True)
session = local.attach(pid)
script = session.create_script(SCRIPT)
script.on('message',message)
script.load()
if not args.attach:
    local.resume(pid)
try:
    time.sleep(180)
finally:
    session.detach()
    print('Captura encerrada; aplicativo permanece aberto.',flush=True)

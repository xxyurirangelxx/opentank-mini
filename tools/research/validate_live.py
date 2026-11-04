"""Sonda temporária: blocos, parâmetros e seleção; nunca envia save flash."""
import importlib.util
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('probe', ROOT / 'probe_readonly.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
scope = probe.load_scope()
events, results = [], []
def received(kind, data, description):
    events.append({'time': time.time(), 'kind': kind, 'hex': data.hex(' ')})
device = scope['MidiDevice'](in_id=0, out_id=1, on_message=received)

def send(raw):
    packet = bytearray(raw)
    packet[-1] = (255 - sum(packet[4:-1])) % 256
    events.append({'time': time.time(), 'kind': 'TX RAW', 'hex': packet.hex(' ')})
    device.send_sysex(scope['encode_sysex'](packet))
    time.sleep(0.12)

def dump():
    start = len(events)
    send(bytes.fromhex('00 59 23 08 00 00 04 00 00 00 10 5c 00 00 8f'))
    end = time.monotonic() + 2
    while time.monotonic() < end:
        for event in events[start:]:
            if event['kind'] != 'IN | SYSEX':
                continue
            raw = scope['decode_sysex'](bytes.fromhex(event['hex']))
            if raw[:4] == bytes.fromhex('00 59 23 64'):
                assert len(raw) == 107 and sum(raw[4:]) % 256 == 255
                return raw[14:-1]
        time.sleep(0.02)
    raise TimeoutError('Sem dump RAM válido')

def toggle(address, value):
    p = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 10 01 00 00 00 00')
    p[7], p[14] = address, value
    send(p)

def knob(address, value):
    p = bytearray.fromhex('00 59 22 0a 00 00 04 00 00 00 10 02 00 00 00 00 00')
    p[7], p[14] = address, value
    send(p)

def select(index):
    p = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 e0 01 00 00 01 00')
    p[7] = index
    send(p)
    time.sleep(0.15)

def record(name, **values):
    entry = dict(test=name, **values)
    results.append(entry)
    print(json.dumps(entry, ensure_ascii=False), flush=True)

before = None
origin = None
try:
    device.open()
    assert device.is_running and device.h_out.value
    backup = (ROOT / 'Tank Mini_AllPresets.atkm').read_bytes()
    assert len(backup) == 1942 and backup[-10:] == b'PATCHEND\0\0'
    slots = [backup[i*92:(i+1)*92] for i in range(21)]
    before = dump()
    matches = [i for i, slot in enumerate(slots) if slot == before]
    assert len(matches) == 1, 'Estado ativo não identifica um único slot do backup'
    origin = matches[0]
    for name, address in [('FX',8), ('AMP',9), ('MOD',10), ('DLY',11), ('REV',12), ('CAB',13)]:
        offset = None
        try:
            toggle(address, 1)
            enabled = dump()
            toggle(address, 0)
            disabled = dump()
            differences = [i for i in range(92) if enabled[i] != disabled[i]]
            assert len(differences) == 1
            offset = differences[0]
            assert offset in range(8,14) and enabled[offset] == 1 and disabled[offset] == 0
            record('toggle '+name, status='PASS', address=address, offset=offset)
        finally:
            if offset is not None:
                toggle(address, before[offset])
            else:
                select(origin)
            assert dump() == before, 'Falha ao restaurar bloco'
    parameters = [(name+' '+str(i+1), base+2*i) for name,base,count in [('FX',20,4),('AMP',32,5),('MOD',44,6),('DLY',56,6),('REV',68,6),('CAB',80,3)] for i in range(count)]
    for name, address in parameters:
        original = int.from_bytes(before[address:address+2], 'little')
        assert 0 <= original <= 100
        temporary = original - 1 if original else 1
        try:
            knob(address, temporary)
            changed = dump()
            differences = [i for i in range(92) if changed[i] != before[i]]
            record('knob '+name, status='PASS' if differences == [address] and changed[address] == temporary else 'FAIL', differences=differences)
        finally:
            knob(address, original)
            assert dump() == before, 'Falha ao restaurar parâmetro'
    for name, address, count in [('FX',14,3),('AMP',15,20),('MOD',16,7),('DLY',17,5),('REV',18,6),('CAB',19,20)]:
        original_model = before[address]
        temporary_model = (original_model+1) % count
        try:
            toggle(address, temporary_model)
            actual = dump()
            record('modelo '+name, status='PASS' if actual[address] == temporary_model else 'FAIL', offset=address, expected=temporary_model, actual=actual[address], differences=[i for i in range(92) if actual[i] != before[i]])
        finally:
            select((origin+1) % 21)
            select(origin)
            assert dump() == before, 'Falha ao restaurar modelo'
    try:
        knob(32, before[32]-1 if before[32] else 1)
        assert dump() != before
        select((origin+1) % 21)
        select(origin)
        assert dump() == before
        record('preview descartado ao trocar preset', status='PASS')
    finally:
        select(origin)
        assert dump() == before
    try:
        for index in range(21):
            select(index)
            actual = dump()
            record('select '+str(index//3+1)+'ABC'[index%3], status='PASS' if actual == slots[index] else 'FAIL', differences=[i for i in range(92) if actual[i] != slots[index][i]])
    finally:
        select(origin)
        assert dump() == before, 'Falha ao restaurar preset original'
    record('restauração final', status='PASS', original_slot=origin)
finally:
    device.close()
    destination = ROOT / ('validation-live-'+time.strftime('%Y%m%d-%H%M%S')+'.json')
    destination.write_text(json.dumps(dict(results=results, events=events), ensure_ascii=False, indent=2), encoding='utf-8')
    print('Registro:', destination, flush=True)

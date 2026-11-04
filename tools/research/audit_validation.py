"""Auditoria offline dos registros e reconstrução do banco lido por USB."""
import importlib.util
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('probe', root/'probe_readonly.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
scope = probe.load_scope()
backup = (root/'Tank Mini_AllPresets.atkm').read_bytes()
for prefix in ('validation-live-', 'validation-ble-'):
    path = max(root.glob(prefix+'*.json'), key=lambda p:p.name)
    report = json.loads(path.read_text(encoding='utf-8'))
    assert report['results'] and all(r['status']=='PASS' for r in report['results'])
    names = [r['test'] for r in report['results']]
    assert sum(n.startswith('toggle ') for n in names) == 6
    assert sum(n.startswith('knob ') for n in names) == 30
    assert sum(n.startswith('modelo ') for n in names) == 6
    assert sum(n.startswith('select ') for n in names) == 21
    assert 'preview descartado ao trocar preset' in names
    assert 'restauração final' in names
    print(path.name, ': blocos=6 parâmetros=30 modelos=6 presets=21; todos PASS')
    if prefix == 'validation-live-':
        dumps = []
        for event in report['events']:
            data = bytes.fromhex(event['hex'])
            if event['kind'] == 'TX RAW':
                assert not (data[:4] == bytes.fromhex('00 59 22 64')), 'Foi enviado comando flash'
            if event['kind'] != 'IN | SYSEX':
                continue
            raw = scope['decode_sysex'](data)
            if raw[:4] == bytes.fromhex('00 59 23 64'):
                assert len(raw)==107 and sum(raw[4:])%256==255
                dumps.append(raw[14:-1])
        readback = b''.join(dumps[-22:-1]) + b'PATCHEND\0\0'
        assert readback == backup
        target = root/'validated-usb-readback.atkm'
        if target.exists():
            assert target.read_bytes()==readback
        else:
            target.write_bytes(readback)
        print('Banco relido idêntico ao backup; SHA-256:', hashlib.sha256(readback).hexdigest())

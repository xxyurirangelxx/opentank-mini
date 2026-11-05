"""Consulta de identificação USB-MIDI, sem edição ou gravação de presets."""
import ast
import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import time

# Sonda historica: o modulo original ficava em outro projeto local.
# O caminho vem do ambiente para o repositorio nao carregar caminho
# de maquina de ninguem.
SOURCE = Path(os.environ.get('TANK_MIDI_SOURCE', 'tank_midi.py'))
ROOT = Path(__file__).resolve().parent

def load_scope():
    tree = ast.parse(SOURCE.read_text(encoding='utf-8-sig'))
    names = {'MIDIINCAPSW', 'MIDIOUTCAPSW', 'MIDIHDR', 'find_midi_ports',
             'MidiDevice', 'encode_sysex', 'decode_sysex'}
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names:
            selected.append(node)
        elif isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Attribute) and isinstance(t.value, ast.Name)
            and t.value.id == 'MIDIHDR' and t.attr == '_fields_'
            for t in node.targets
        ):
            selected.append(node)
    scope = dict(ctypes=ctypes, wintypes=wintypes, time=time,
                 winmm=ctypes.windll.winmm, MIM_DATA=0x3C3,
                 MIM_LONGDATA=0x3C4, decode_raw_mvave=lambda raw: raw.hex(' '),
                 format_preset=lambda value: str(value))
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(SOURCE), 'exec'), scope)
    return scope

def main():
    scope = load_scope()
    events = []
    def received(kind, data, description):
        item = {'time': time.time(), 'kind': kind, 'hex': data.hex(' '),
                'description': description}
        events.append(item)
        print(json.dumps(item, ensure_ascii=False), flush=True)
    device = scope['MidiDevice'](in_id=0, out_id=1, on_message=received)
    import sys
    mode = 'fx-preview' if '--fx-preview' in sys.argv else ('ram' if '--ram' in sys.argv else 'identity')
    request = bytes.fromhex('00 59 23 08 00 00 04 00 00 00 10 5c 00 00 8f' if mode != 'identity' else '00 59 11 00 00 00 ff')
    if (sum(request[4:]) & 0xff) != 0xff:
        raise ValueError('Checksum da consulta inválido.')
    frame = scope['encode_sysex'](request)
    print('Identificação TX:', frame.hex(' '), flush=True)
    try:
        device.open()
        if not device.is_running or not device.h_out.value:
            raise RuntimeError('Não foi possível abrir as duas portas MIDI.')
        device.send_sysex(frame)
        time.sleep(3)
        if mode == 'fx-preview':
            def latest_dump(start):
                for event in reversed(events[start:]):
                    raw = scope['decode_sysex'](bytes.fromhex(event['hex']))
                    if raw[:4] == bytes.fromhex('00 59 23 64'):
                        assert len(raw) == 107 and sum(raw[4:]) % 256 == 255
                        return raw[14:-1]
                raise RuntimeError('Nenhum dump válido recebido.')
            before = latest_dump(0)
            backup = (ROOT / 'Tank Mini_AllPresets.atkm').read_bytes()
            assert any(backup[i*92:(i+1)*92] == before for i in range(21))
            original = before[8]
            assert original in (0, 1)
            def toggle(value):
                packet = bytearray.fromhex('00 59 22 09 00 00 04 08 00 00 10 01 00 00 00 00')
                packet[14] = value
                packet[-1] = (255 - sum(packet[4:-1])) % 256
                print('TX toggle FX:', packet.hex(' '), flush=True)
                device.send_sysex(scope['encode_sysex'](packet))
                time.sleep(0.3)
            def read_dump():
                start = len(events)
                device.send_sysex(frame)
                time.sleep(1)
                return latest_dump(start)
            try:
                toggle(1 - original)
                changed = read_dump()
                differences = [i for i in range(92) if before[i] != changed[i]]
                print('Offsets alterados:', differences, flush=True)
                assert differences == [8] and changed[8] == 1 - original
            finally:
                toggle(original)
                restored = read_dump()
                assert restored == before, 'Restauração não confirmada!'
                print('Restauração confirmada: 92 bytes idênticos.', flush=True)
    finally:
        device.close()
        result = {'request_raw': request.hex(' '), 'request_sysex': frame.hex(' '),
                  'events': events}
        (ROOT / f'probe_{mode}_result.json').write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Total de eventos:', len(events), flush=True)

if __name__ == '__main__':
    main()

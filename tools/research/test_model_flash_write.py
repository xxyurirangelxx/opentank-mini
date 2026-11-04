"""Grava um registro ALTERADO no bloco AMP 1, confere e restaura.

Fluxo sem commit (o commit de area 0x05 descarta a gravacao).
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, SCOPE, Tank, read_request  # noqa: E402

REF = ROOT.parent.parent / 'research' / 'dumps' / 'factory-am4-buffer.bin'
BASE = 0x70000000
CHUNK = 1015
ACK = bytes.fromhex('00 59 00 01 00 00 00 ff')


def exchange(tank, frame, timeout=3.0):
    start = len(tank.events)
    tank.send(frame, settle=0.0)
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for event in tank.events[start:]:
            if event['kind'] != 'IN | SYSEX':
                continue
            raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
            if raw[:2] == bytes.fromhex('00 59'):
                return raw
        time.sleep(0.01)
    return None


def read_checked(tank, address, length, timeout=2.0):
    start = len(tank.events)
    tank.send(read_request(address, length, AREA_AMP), settle=0.0)
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for event in tank.events[start:]:
            if event['kind'] != 'IN | SYSEX':
                continue
            raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
            if raw[:3] != bytes.fromhex('00 59 23'):
                continue
            echoed = raw[7] | (raw[8] << 8) | (raw[9] << 16) | (raw[10] << 24)
            if echoed == address:
                return raw[14:-1]
        time.sleep(0.005)
    raise TimeoutError('sem resposta para %#x' % address)


def read_block(tank, address, length):
    out = b''
    while len(out) < length:
        out += read_checked(tank, address + len(out),
                            min(431, length - len(out)))
    return out


def erase(tank, address):
    frame = bytearray([0x00, 0x59, 0x21, 0x05, 0x00, 0x00, 0x05])
    frame += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    frame += bytes([0x00])
    reply = exchange(tank, bytes(frame))
    assert reply and reply[:8] == ACK, reply.hex(' ') if reply else 'sem resposta'


def write(tank, address, payload):
    frame = bytearray([0x00, 0x59, 0x22])
    frame += (len(payload) + 8).to_bytes(2, 'little')
    frame += bytes([0x00, 0x05])
    frame += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    frame += len(payload).to_bytes(2, 'little')
    frame += bytes([0x00]) + payload + bytes([0x00])
    reply = exchange(tank, bytes(frame))
    assert reply and reply[:8] == ACK, hex(address)


def write_record(tank, address, record):
    erase(tank, address)
    erase(tank, address + 4096)
    for offset in range(0, len(record), CHUNK):
        write(tank, address + offset, record[offset:offset + CHUNK])


original = REF.read_bytes()[:8192]
mutated = bytearray(original)
mutated[4:18] = b'OPENTANK_TEST\x00'

with Tank() as tank:
    before = read_block(tank, BASE, 8192)
    print('antes identico ao backup:', before == original, flush=True)

    print('gravando registro alterado...', flush=True)
    write_record(tank, BASE, bytes(mutated))
    live = read_block(tank, BASE, 8192)
    print('  alterado persistiu:', live == bytes(mutated), flush=True)
    print('  nome lido:', live[4:18], flush=True)

    print('restaurando original...', flush=True)
    write_record(tank, BASE, original)
    live = read_block(tank, BASE, 8192)
    print('  restaurado:', live == original, flush=True)
    print('  nome lido:', live[4:18], flush=True)

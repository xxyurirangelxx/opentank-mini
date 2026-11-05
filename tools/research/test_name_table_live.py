"""A tabela de nomes (`0x90000000`) acompanha a gravacao na flash?

Grava o registro do AMP 1 com um nome diferente, le a tabela de novo e
restaura o bloco original. Responde se a tabela e uma fonte viva ou um espelho
gerado apenas no boot; isso decide se o app pode usa-la como fonte de nomes.

Somente toca no AMP 1; o conteudo original e lido antes e reposto no final.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, SCOPE, Tank, read_request  # noqa: E402

BASE = 0x70000000
TABLE = 0x90000000
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


def table_names(tank):
    blob = read_checked(tank, TABLE, 280)
    return [blob[i:i + 14].split(b'\0')[0].decode('ascii', 'replace')
            for i in range(0, len(blob), 14)]


with Tank() as tank:
    original = read_block(tank, BASE, 8192)
    print('AMP 1 atual:', original[4:18], flush=True)
    print('tabela antes:', table_names(tank)[:3], flush=True)

    mutated = bytearray(original)
    mutated[4:18] = b'OPENTANK_LIVE\x00'
    write_record(tank, BASE, bytes(mutated))

    table = table_names(tank)
    print('tabela depois da gravacao:', table[:3], flush=True)
    print('  tabela seguiu a flash:', table[0] == 'OPENTANK_LIVE', flush=True)

    write_record(tank, BASE, original)
    back = read_block(tank, BASE, 8192)
    print('flash restaurada:', back == original, flush=True)
    print('tabela depois de restaurar:', table_names(tank)[:3], flush=True)
    if back != original:
        raise SystemExit('RESTAURACAO FALHOU')

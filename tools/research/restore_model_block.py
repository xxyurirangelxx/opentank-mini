"""Restaura o bloco AMP 20 da flash de modelos a partir do backup de fabrica.

Apaga os dois setores, escreve em blocos de 1015 bytes, commita e confere.
Mostra o ACK de cada comando para nao travar em silencio.
"""
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tankbase import AREA_AMP, Tank, read_request  # noqa: E402

BACKUP = ROOT.parent.parent / 'research' / 'dumps' / 'factory-am4-buffer.bin'
INDEX = 0
ADDRESS = 0x70000000 + INDEX * 8192
SECTOR = 4096
CHUNK = 1015
ACK = bytes.fromhex('00 59 00 01 00 00 00 ff')


def read_fast(tank, address, length, timeout=2.0):
    """Le e so aceita a resposta que ECOA o endereco e o tamanho pedidos.

    Sem essa checagem uma resposta atrasada de outro chunk entra no lugar do
    certo e a releitura "identica" vira falsa.
    """
    from tankbase import SCOPE
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
            size = raw[11] | (raw[12] << 8)
            if echoed == address and size == length:
                return raw[14:-1]
        time.sleep(0.005)
    raise TimeoutError(f'sem resposta valida para {address:#x}')


def read_block(tank, address, length):
    out = b''
    while len(out) < length:
        out += read_fast(tank, address + len(out), min(431, length - len(out)))
    return out


def send_checked(tank, frame, label):
    start = len(tank.events)
    tank.send(frame, settle=0.03)
    reply = tank.wait_response(bytes.fromhex('00 59'), timeout=3.0, start=start)
    if reply[:8] != ACK:
        raise SystemExit(f'{label}: recusado -> {reply.hex(" ")}')


def erase(tank, address):
    frame = bytearray([0x00, 0x59, 0x21, 0x05, 0x00, 0x00, 0x05])
    frame += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    frame += bytes([0x00])
    assert len(frame) == 12
    send_checked(tank, bytes(frame), f'erase {address:#x}')


def write(tank, address, payload):
    frame = bytearray([0x00, 0x59, 0x22])
    frame += (len(payload) + 8).to_bytes(2, 'little')
    frame += bytes([0x00, 0x05])
    frame += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    frame += len(payload).to_bytes(2, 'little')
    frame += bytes([0x00]) + payload + bytes([0x00])
    send_checked(tank, bytes(frame), f'write {address:#x}')


def commit(tank):
    send_checked(tank,
                 bytes.fromhex('00 59 22 08 00 00 05 00 00 00 F0 00 00 00 00'),
                 'commit')


backup = BACKUP.read_bytes()
record = backup[INDEX * 8192:(INDEX + 1) * 8192]
print('restaurando bloco', INDEX, 'em', hex(ADDRESS), 'nome', record[4:18])

with Tank() as tank:
    for sector in (ADDRESS, ADDRESS + SECTOR):
        erase(tank, sector)
        print('  apagado', hex(sector), flush=True)
    for offset in range(0, len(record), CHUNK):
        write(tank, ADDRESS + offset, record[offset:offset + CHUNK])
    # NAO enviar commit: o restore de modelos do editor nao manda nenhum, e um
    # commit com area 0x05 faz o pedal descartar a gravacao.
    print('  escritas enviadas', flush=True)

    live = read_block(tank, ADDRESS, len(record))
    print('releitura identica ao backup:', live == record)
    if live != record:
        diff = [k for k in range(len(record)) if live[k] != record[k]]
        print('  diferenças:', len(diff), diff[:10])

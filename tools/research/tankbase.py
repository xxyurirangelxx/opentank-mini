"""Base reutilizável das sondas de protocolo (temporária, não é código de produto)."""
import importlib.util
import json
from pathlib import Path
import time

ROOT = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('probe', ROOT / 'probe_readonly.py')
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)
SCOPE = probe.load_scope()

RAM_REQUEST = bytes.fromhex('00 59 23 08 00 00 04 00 00 00 10 5c 00 00 8f')
GLOBAL_REQUEST = bytes.fromhex('00 59 23 08 00 00 04 00 00 00 20 04 00 00 d7')

AREA_PRESETS = 0x04   # banco de presets (flash 92 B/slot, RAM em 0x10000000)
AREA_AMP = 0x05       # buffer de AMP (8192 B, cabecalho "AM2\0")
RAM_ADDRESS = 0x10000000
MAX_READ = 431        # limite fisico por comando de leitura (resposta SysEx 512 B)


def checksum(raw):
    """Checksum cobre do indice 5 ate o penultimo byte.

    Layout: 00 59 cmd | len LE16 | 00 | area | ...
    O primeiro byte da area esta no indice 5, por isso o calculo comeca ali.
    """
    return (255 - sum(raw[5:-1])) % 256


def seal(raw):
    packet = bytearray(raw)
    packet[-1] = checksum(packet)
    return bytes(packet)


def read_request(address, length, area=AREA_PRESETS):
    """Leitura: 00 59 23 | 08 00 | 00 | area | addr LE32 | len LE16 | 00 | cs."""
    packet = bytearray([0x00, 0x59, 0x23, 0x08, 0x00, 0x00, area])
    packet += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    packet += (length & 0xFFFF).to_bytes(2, 'little')
    packet.append(0x00)
    packet.append(0)
    return seal(packet)


def write_request(address, payload, area=AREA_PRESETS):
    """Escrita: 00 59 22 | (tam+8) LE16 | 00 | area | addr LE32 | tam LE16 | 00 | payload | cs."""
    size = len(payload)
    packet = bytearray([0x00, 0x59, 0x22])
    packet += (size + 8).to_bytes(2, 'little')
    packet.append(0x00)
    packet.append(area)
    packet += (address & 0xFFFFFFFF).to_bytes(4, 'little')
    packet += size.to_bytes(2, 'little')
    packet.append(0x00)
    packet += payload
    packet.append(0)
    return seal(packet)


class Tank:
    def __init__(self, in_id=0, out_id=1):
        self.events = []
        self.device = SCOPE['MidiDevice'](in_id=in_id, out_id=out_id,
                                           on_message=self._on_message)

    def _on_message(self, kind, data, description):
        self.events.append({'time': time.time(), 'kind': kind,
                            'hex': data.hex(' ')})

    def open(self):
        self.device.open()
        if not self.device.is_running or not self.device.h_out.value:
            raise RuntimeError('Não foi possível abrir as duas portas MIDI.')
        return self

    def close(self):
        self.device.close()

    def __enter__(self):
        return self.open()

    def __exit__(self, *exc):
        self.close()

    def send(self, raw, settle=0.12):
        packet = bytearray(raw)
        packet[-1] = checksum(packet)
        self.events.append({'time': time.time(), 'kind': 'TX RAW',
                            'hex': packet.hex(' ')})
        self.device.send_sysex(SCOPE['encode_sysex'](packet))
        time.sleep(settle)
        return bytes(packet)

    def send_sysex(self, frame, settle=0.12):
        self.events.append({'time': time.time(), 'kind': 'TX SYSEX',
                            'hex': frame.hex(' ')})
        self.device.send_sysex(frame)
        time.sleep(settle)

    def responses(self):
        for event in self.events:
            if event['kind'] != 'IN | SYSEX':
                continue
            yield SCOPE['decode_sysex'](bytes.fromhex(event['hex']))

    def wait_response(self, prefix, timeout=3.0, expected_len=None, start=None):
        if start is None:
            start = len(self.events)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            for event in self.events[start:]:
                if event['kind'] != 'IN | SYSEX':
                    continue
                raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
                if not raw.startswith(prefix):
                    continue
                if expected_len is not None and len(raw) != expected_len:
                    continue
                return raw
            time.sleep(0.02)
        raise TimeoutError('Sem resposta %s' % prefix.hex(' '))

    def dump(self, request=RAM_REQUEST, timeout=2.0):
        start = len(self.events)
        self.send(request)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            for event in self.events[start:]:
                if event['kind'] != 'IN | SYSEX':
                    continue
                raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
                if raw[:4] == bytes.fromhex('00 59 23 64') and len(raw) == 107:
                    assert sum(raw[4:]) % 256 == 255
                    return raw[14:-1]
            time.sleep(0.02)
        raise TimeoutError('Sem dump RAM válido')

    def read(self, address, length=92, area=AREA_PRESETS, timeout=2.0):
        """Lê até MAX_READ bytes. Retorna None em endereço inválido (ACK negativo)."""
        assert 0 < length <= MAX_READ
        start = len(self.events)
        self.send(read_request(address, length, area), settle=0.5)
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            for event in self.events[start:]:
                if event['kind'] != 'IN | SYSEX':
                    continue
                raw = SCOPE['decode_sysex'](bytes.fromhex(event['hex']))
                if (raw[:3] == bytes.fromhex('00 59 23') and len(raw) >= 16
                        and (255 - sum(raw[5:-1])) % 256 == raw[-1]):
                    # header de 14 bytes; payload = raw[14:-1]
                    return raw[14:-1]
                if raw[:4] == bytes.fromhex('00 59 00 01'):
                    return None
            time.sleep(0.02)
        raise TimeoutError('Sem resposta de leitura em %08X' % address)

    def read_block(self, address, length, area=AREA_PRESETS, timeout=2.0):
        out = bytearray()
        while len(out) < length:
            chunk = self.read(address + len(out),
                              min(MAX_READ, length - len(out)), area,
                              timeout=timeout)
            if chunk is None:
                raise ValueError('Endereço inválido %08X' % (address + len(out)))
            out += chunk
        return bytes(out)

    def write(self, address, payload, area=AREA_PRESETS, settle=0.3, timeout=2.0):
        """Envia escrita e devolve a resposta bruta (ACK ou negativo)."""
        start = len(self.events)
        self.send(write_request(address, payload, area), settle=0.05)
        try:
            return self.wait_response(bytes.fromhex('00 59'), timeout=timeout,
                                      start=start)
        except TimeoutError:
            return None

    def commit(self, settle=0.5):
        return self.send(bytes.fromhex('00 59 22 08 00 00 04 00 00 00 F0 00 00 00 0B'),
                         settle=settle)

    def toggle(self, address, value):
        p = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 10 01 00 00 00 00')
        p[7], p[14] = address, value
        return self.send(p)

    def knob(self, address, value):
        p = bytearray.fromhex('00 59 22 0a 00 00 04 00 00 00 10 02 00 00 00 00 00')
        p[7], p[14] = address, value
        return self.send(p)

    def select(self, index):
        p = bytearray.fromhex('00 59 22 09 00 00 04 00 00 00 e0 01 00 00 01 00')
        p[7] = index
        self.send(p)
        time.sleep(0.15)

    def select_confirm(self, index, expected, timeout=3.0):
        """Seleciona e espera a RAM convergir para o preset esperado."""
        self.select(index)
        end = time.monotonic() + timeout
        reads = 0
        while time.monotonic() < end:
            reads += 1
            if self.dump() == expected:
                return reads
            time.sleep(0.1)
        raise TimeoutError('Seleção %d não convergiu' % index)


def save_log(path, payload):
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2),
                          encoding='utf-8')


def backup_slots(root=ROOT):
    backup = (root / 'Tank Mini_AllPresets.atkm').read_bytes()
    assert len(backup) == 1942 and backup[-10:] == b'PATCHEND\0\0'
    return [backup[i*92:(i+1)*92] for i in range(21)]

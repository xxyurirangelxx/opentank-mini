"""Escuta mensagens MIDI curtas E SysEx do pedal, na mesma sessao.

Heartbeat costuma ser Active Sensing (`FE`), entregue como mensagem curta.
Um unico callback trata os dois casos; a porta e aberta uma vez so.
"""
import ctypes
import time
from ctypes import wintypes

CALLBACK_FUNCTION = 0x00030000
MIM_DATA = 0x3C3
MIM_LONGDATA = 0x3C4
MIM_LONGERROR = 0x3C6

CALLBACK = ctypes.CFUNCTYPE(
    None, wintypes.HANDLE, wintypes.UINT, ctypes.c_void_p,
    ctypes.c_void_p, ctypes.c_void_p,
)


class MIDIHDR(ctypes.Structure):
    _fields_ = [
        ('lpData', ctypes.c_void_p), ('dwBufferLength', wintypes.DWORD),
        ('dwBytesRecorded', wintypes.DWORD), ('dwUser', ctypes.c_void_p),
        ('dwFlags', wintypes.DWORD), ('lpNext', ctypes.c_void_p),
        ('reserved', ctypes.c_void_p), ('dwOffset', wintypes.DWORD),
        ('dwReserved', ctypes.c_void_p * 8),
    ]


winmm = ctypes.WinDLL('winmm')
winmm.midiInOpen.argtypes = [
    ctypes.POINTER(wintypes.HANDLE), wintypes.UINT, ctypes.c_void_p,
    ctypes.c_void_p, wintypes.DWORD,
]
winmm.midiInPrepareHeader.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.UINT]
winmm.midiInAddBuffer.argtypes = [
    wintypes.HANDLE, ctypes.c_void_p, wintypes.UINT]

events = []
t0 = time.monotonic()
buffers = []
headers = []


def on_event(handle, message, instance, param1, param2):
    if message == MIM_DATA:
        value = param1 or 0
        events.append(('SHORT', time.monotonic() - t0, value))
        return
    if message in (MIM_LONGDATA, MIM_LONGERROR):
        header = ctypes.cast(param1, ctypes.POINTER(MIDIHDR)).contents
        data = ctypes.string_at(header.lpData, header.dwBytesRecorded)
        events.append(('LONG', time.monotonic() - t0, data))
        winmm.midiInAddBuffer(handle, param1, ctypes.sizeof(MIDIHDR))


callback = CALLBACK(on_event)
handle = wintypes.HANDLE()
result = winmm.midiInOpen(ctypes.byref(handle), 0, callback, None,
                          CALLBACK_FUNCTION)
print('midiInOpen =', result)
if result != 0:
    raise SystemExit('nao abriu a porta')

for _ in range(4):
    buf = ctypes.create_string_buffer(1024)
    hdr = MIDIHDR()
    hdr.lpData = ctypes.cast(buf, ctypes.c_void_p)
    hdr.dwBufferLength = 1024
    winmm.midiInPrepareHeader(handle, ctypes.byref(hdr), ctypes.sizeof(MIDIHDR))
    winmm.midiInAddBuffer(handle, ctypes.byref(hdr), ctypes.sizeof(MIDIHDR))
    buffers.append(buf)
    headers.append(hdr)

winmm.midiInStart(handle)
print('escutando 15s sem enviar nada...', flush=True)
time.sleep(15)
winmm.midiInStop(handle)

print('total de eventos:', len(events))
if not events:
    print('  nada: o pedal nao emite Active Sensing nem SysEx espontaneo')

gaps = []
previous = None
for kind, when, payload in events[:60]:
    gap = ''
    if previous is not None:
        delta = when - previous
        gaps.append(delta)
        gap = f' (+{delta:.3f}s)'
    previous = when
    if kind == 'SHORT':
        status = payload & 0xFF
        label = {0xFE: 'Active Sensing', 0xF8: 'Clock', 0xFA: 'Start',
                 0xFB: 'Continue', 0xFC: 'Stop'}.get(status, '?')
        print(f'  t={when:6.2f}s{pad} SHORT 0x{payload:06x} {label}'.format(
            pad='' if not gap else gap) + gap)
    else:
        print(f'  t={when:6.2f}s{gap} LONG  {payload.hex(" ")[:60]}')

if gaps:
    print(f'intervalo medio: {sum(gaps) / len(gaps):.3f}s '
          f'(min {min(gaps):.2f}s, max {max(gaps):.2f}s)')

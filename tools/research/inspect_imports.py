"""Inspeção estática de imports e strings de comunicação, sem carregar DLLs."""
from pathlib import Path
import re
import pefile
root = Path(__file__).resolve().parent/'capture-input'/'m-efcs'
for name in ['data/app.so']:
    path = root/name
    try:
        pe = pefile.PE(str(path))
    except pefile.PEFormatError:
        pe = None
    print('\nARQUIVO',name)
    for entry in getattr(pe,'DIRECTORY_ENTRY_IMPORT',[]):
        functions = [i.name.decode('ascii','replace') for i in entry.imports if i.name]
        filtered = [f for f in functions if re.search('midi|hid|usb|CreateFile|WriteFile|ReadFile|DeviceIo|GetProc|LoadLibrary',f,re.I)]
        print(entry.dll.decode(), filtered)
    strings = re.findall(rb'[\x20-\x7e]{5,}',path.read_bytes())
    selected = sorted({s.decode('ascii') for s in strings if re.search(rb'midi|hid_|winusb|usb-midi|tuner|loopback|swap|bypass',s,re.I)})
    for value in selected[:120]:
        print(value[:300])

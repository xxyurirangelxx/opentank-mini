"""Inspeciona somente a janela do processo de teste do M-EFCS."""
from pathlib import Path
from pywinauto import Application
ROOT = Path(__file__).resolve().parent
pid = int((ROOT/'capture-mefcs-pid.txt').read_text())
app = Application(backend='win32').connect(process=pid, timeout=10)
for window in app.windows():
    print('JANELA', window.handle, repr(window.window_text()), window.rectangle(), flush=True)
    if window.is_visible():
        window.set_focus()
        window.capture_as_image().save(ROOT/'editor-window.png')
        app.window(handle=window.handle).print_control_identifiers(depth=3)

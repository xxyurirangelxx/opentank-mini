"""Clique pontual na janela isolada do editor; coordenadas relativas à janela."""
from pathlib import Path
import sys
import time
from pywinauto import Application
ROOT = Path(__file__).resolve().parent
pid = int((ROOT/'capture-mefcs-pid.txt').read_text())
window = Application(backend='win32').connect(process=pid).window(class_name='FLUTTER_RUNNER_WIN32_WINDOW')
window.set_focus()
if len(sys.argv) == 3:
    x, y = map(int, sys.argv[1:])
    rect = window.rectangle()
    assert 0 <= x < rect.width() and 0 <= y < rect.height()
    import json
    with (ROOT/'editor-actions.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps(dict(time=time.time(), x=x, y=y))+'\n')
    window.click_input(coords=(x,y))
    time.sleep(0.7)
window.capture_as_image().save(ROOT/'editor-window.png')

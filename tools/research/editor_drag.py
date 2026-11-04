"""Sonda de mudança reversível da cadeia pela interface oficial."""
from pathlib import Path
import json
import sys
import time
from pywinauto import Application
root=Path(__file__).resolve().parent
pid=int((root/'capture-mefcs-pid.txt').read_text())
window=Application(backend='win32').connect(process=pid).window(class_name='FLUTTER_RUNNER_WIN32_WINDOW')
window.set_focus()
x1,y1,x2,y2=map(int,sys.argv[1:])
with (root/'editor-actions.jsonl').open('a',encoding='utf-8') as log:
    log.write(json.dumps(dict(time=time.time(),drag=[x1,y1,x2,y2]))+'\n')
window.drag_mouse_input(dst=(x2,y2),src=(x1,y1))
time.sleep(0.5)
window.capture_as_image().save(root/'editor-window.png')

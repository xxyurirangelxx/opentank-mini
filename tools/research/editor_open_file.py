"""Seleciona arquivo local no diálogo nativo do processo de teste."""
from pathlib import Path
import sys
from pywinauto import Application
root=Path(__file__).resolve().parent
pid=int((root/'capture-mefcs-pid.txt').read_text())
path=Path(sys.argv[1]).resolve()
assert path.is_file()
app=Application(backend='win32').connect(process=pid)
dialog=app.window(title='File Picker',class_name='#32770')
dialog['Edit'].set_edit_text(str(path))
dialog.child_window(title='&Abrir',class_name='Button').click()
print('Arquivo selecionado:',path)

"""Compila o app para Windows e gera o instalador .exe.

Uso:
    python tools/build_installer.py            # compila e empacota
    python tools/build_installer.py --skip-build   # so empacota o que existe

Requer, para a etapa do instalador:
- Inno Setup 6 (`ISCC.exe`). Se nao estiver instalado, o script tenta instalar
  via winget/choco; sem permissao, imprime o link e a linha de instalacao.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'app'
ISS = ROOT / 'packaging' / 'windows' / 'opentank-mini.iss'
DIST = ROOT / 'dist'


def flutter():
    for candidate in (
        os.environ.get('FLUTTER'),
        shutil.which('flutter'),
        Path.home() / 'tools-sdk' / 'flutter' / 'bin' / 'flutter.bat',
        Path.home() / 'tools-sdk' / 'flutter' / 'bin' / 'flutter',
    ):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def run(cmd, cwd=None, check=True):
    print('>', ' '.join(str(c) for c in cmd), flush=True)
    proc = subprocess.run(cmd, cwd=str(cwd) if cwd else None)
    if check and proc.returncode != 0:
        raise SystemExit(f'falhou ({proc.returncode}): {cmd[0]}')
    return proc.returncode


def version():
    """Le a versao do pubspec (linha `version: 1.0.0+1`)."""
    for line in (APP / 'pubspec.yaml').read_text(encoding='utf-8').splitlines():
        if line.startswith('version:'):
            return line.split(':', 1)[1].strip().split('+')[0]
    return '1.0.0'


def find_iscc():
    local = os.environ.get('LOCALAPPDATA')
    for path in (
        os.environ.get('ISCC'),
        r'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        r'C:\Program Files\Inno Setup 6\ISCC.exe',
        # O winget instala por usuario quando nao ha elevacao.
        (Path(local) / 'Programs' / 'Inno Setup 6' / 'ISCC.exe')
        if local
        else None,
        shutil.which('iscc'),
        shutil.which('ISCC'),
    ):
        if path and Path(path).exists():
            return str(path)
    return None


def install_iscc():
    """Tenta instalar o Inno Setup pelos gerenciadores disponiveis."""
    attempts = []
    if shutil.which('winget'):
        attempts.append(
            ['winget', 'install', '--id', 'JRSoftware.InnoSetup',
             '--accept-package-agreements', '--accept-source-agreements',
             '--silent']
        )
    if shutil.which('choco'):
        attempts.append(['choco', 'install', 'innosetup', '-y'])
    for cmd in attempts:
        print(f'tentando instalar o Inno Setup com: {cmd[0]}', flush=True)
        code = run(cmd, check=False)
        found = find_iscc()
        if found:
            return found
        print(f'  {cmd[0]} terminou com {code} e o ISCC nao apareceu', flush=True)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-build', action='store_true',
                        help='nao recompila o Flutter')
    args = parser.parse_args()

    release = APP / 'build' / 'windows' / 'x64' / 'runner' / 'Release'
    if not args.skip_build:
        tool = flutter()
        if tool is None:
            raise SystemExit('flutter nao encontrado; defina a variavel FLUTTER')
        # `--no-tree-shake-icons` e proposital: o subconjunto de icones gerado
        # e reutilizado do cache e nao invalidava quando a interface mudava,
        # fazendo icones novos aparecerem como quadrado vazio.
        run(
            [tool, 'build', 'windows', '--release', '--no-tree-shake-icons'],
            cwd=APP,
        )

    exe = release / 'opentank_mini.exe'
    if not exe.exists():
        raise SystemExit(f'build ausente: {exe}\nRode sem --skip-build.')

    iscc = find_iscc() or install_iscc()
    if iscc is None:
        print()
        print('Inno Setup nao encontrado e nao foi possivel instalar.')
        print('Instale manualmente: https://jrsoftware.org/isdl.php')
        print('Ou: winget install --id JRSoftware.InnoSetup')
        print()
        print(f'O app compilado esta em: {release}')
        print('Depois de instalar o Inno Setup, rode este script de novo.')
        return 1

    ver = version()
    DIST.mkdir(exist_ok=True)
    run([iscc, f'/DAppVersion={ver}', str(ISS)], cwd=ROOT)

    made = sorted(DIST.glob('OpenTankMini-*-windows-x64.exe'))
    if not made:
        raise SystemExit('o Inno Setup nao gerou o instalador')
    for path in made:
        size = path.stat().st_size / (1024 * 1024)
        print(f'\ninstalador: {path}  ({size:.1f} MB)')
    return 0


if __name__ == '__main__':
    sys.exit(main())

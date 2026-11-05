"""Verificação do repositório — reproduz o CI localmente e confere artefatos.

Uso:
    python tools/verify_repo.py            # roda tudo
    python tools/verify_repo.py --quick    # pula testes e builds

Sai com código 0 só se tudo passar. Cada item imprime PASS/FAIL com a
evidência (arquivo, linha ou saída do comando).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'app'

PASS, FAIL, SKIP = 'PASS', 'FAIL', 'SKIP'
results = []


def record(name, status, evidence):
    results.append((name, status, evidence))
    print(f'[{status}] {name}: {evidence}', flush=True)


def flutter_cmd():
    for candidate in (
        os.environ.get('FLUTTER'),
        shutil.which('flutter'),
        r'C:\Users\Yuri Rangel\tools-sdk\flutter\bin\flutter.bat',
        r'C:\Users\Yuri Rangel\tools-sdk\flutter\bin\flutter',
    ):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def run(cmd, cwd, timeout=600):
    try:
        proc = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True,
            timeout=timeout, encoding='utf-8', errors='replace',
        )
        return proc.returncode, (proc.stdout or '') + (proc.stderr or '')
    except Exception as error:  # noqa: BLE001
        return 127, f'{error}'


def check_files():
    required = {
        'app/lib/core/protocol/messages.dart': 'comandos do protocolo',
        'app/lib/core/protocol/packing.dart': 'empacotamento 7 bits',
        'app/lib/core/model/preset.dart': 'layout do preset',
        'app/lib/core/model/preset_bank.dart': 'banco .atkm',
        'app/lib/core/model/model_format.dart': 'buffer AMP/CAB',
        'app/lib/core/model/model_flash.dart': 'flash de modelos',
        'app/lib/core/device/tank_device.dart': 'cliente do dispositivo',
        'app/lib/platform/midi_transport.dart': 'transporte USB',
        'app/lib/platform/ble_transport.dart': 'transporte BLE',
        'app/lib/state/tank_controller.dart': 'controlador',
        'app/lib/ui/screens/home_screen.dart': 'editor',
        'app/lib/ui/screens/import_screen.dart': 'importar AMP/CAB',
        'app/lib/ui/screens/settings_screen.dart': 'ajustes e backup',
        'docs/PROTOCOL.md': 'protocolo',
        'docs/VALIDATION.md': 'validação',
        'docs/ARCHITECTURE.md': 'arquitetura',
        'README.md': 'apresentação',
        'LICENSE': 'licença',
        'CONTRIBUTING.md': 'guia de contribuição',
        'CODE_OF_CONDUCT.md': 'código de conduta',
        'CHANGELOG.md': 'histórico',
        '.github/workflows/ci.yml': 'CI',
        'research/fixtures/Tank Mini_AllPresets.atkm': 'banco de teste',
        'research/dumps/factory-am4-buffer.bin': 'flash de referência',
    }
    missing = [p for p in required if not (ROOT / p).exists()]
    if missing:
        record('arquivos obrigatórios', FAIL, f'faltam {missing}')
    else:
        record('arquivos obrigatórios', PASS, f'{len(required)} arquivos presentes')


def check_docs():
    facts = [
        ('docs/PROTOCOL.md', r'começa no índice 5', 'checksum no índice 5'),
        ('docs/PROTOCOL.md', r'0x70000000', 'endereço da flash de modelos'),
        ('docs/PROTOCOL.md', r'Não há commit', 'ausência de commit no modelo'),
        ('docs/PROTOCOL.md', r'0x10000000 \+ offset', 'endereço de tempo real'),
        ('docs/PROTOCOL.md', r'431', 'limite de leitura'),
        ('docs/PROTOCOL.md', r'1015', 'limite de escrita'),
        ('docs/VALIDATION.md', r'21/21', 'banco verificado'),
        ('docs/VALIDATION.md', r'30/30', 'flash verificada'),
        ('docs/VALIDATION.md', r'[Pp]ower-cycle', 'lacuna do power-cycle'),
        ('README.md', r'M-VAVE Tank Mini', 'apresenta o produto'),
        ('README.md', r'MIT', 'licença citada'),
    ]
    bad = []
    for path, pattern, label in facts:
        text = (ROOT / path).read_text(encoding='utf-8')
        if not re.search(pattern, text):
            bad.append(label)
    if bad:
        record('documentação', FAIL, f'falta em docs: {bad}')
    else:
        record('documentação', PASS, f'{len(facts)} afirmações conferidas')


def check_code_rules():
    """Regras que, se violadas, corrompem o pedal."""
    checks = [
        ('app/lib/core/device/tank_device.dart', r'commit: false',
         'modelo grava sem commit'),
        ('app/lib/core/device/tank_device.dart', r'echoed != address',
         'leitura valida o endereço ecoado'),
        ('app/lib/core/protocol/messages.dart', r'for \(var i = 5',
         'checksum começa no índice 5'),
        ('app/lib/core/model/model_flash.dart', r'0x70000000',
         'flash de modelos no endereço certo'),
    ]
    bad = []
    for path, pattern, label in checks:
        text = (ROOT / path).read_text(encoding='utf-8')
        if not re.search(pattern, text):
            bad.append(label)
    if bad:
        record('regras de protocolo', FAIL, f'violadas: {bad}')
    else:
        record('regras de protocolo', PASS, f'{len(checks)} regras presentes')


def check_tests(quick):
    if quick:
        record('testes', SKIP, '--quick')
        return
    code, out = run([flutter_cmd(), 'test'], APP)
    match = re.search(r'\+(\d+)(?: -\d+)?: All tests passed!', out)
    if code == 0 and match:
        record('testes', PASS, f'{match.group(1)} testes passaram')
    else:
        tail = out.strip().splitlines()[-3:]
        record('testes', FAIL, ' | '.join(tail))


def check_analyze(quick):
    if quick:
        record('análise estática', SKIP, '--quick')
        return
    code, out = run([flutter_cmd(), 'analyze', '--fatal-infos'], APP)
    if code == 0 and 'No issues found' in out:
        record('análise estática', PASS, 'flutter analyze --fatal-infos limpo')
    else:
        tail = out.strip().splitlines()[-3:]
        record('análise estática', FAIL, ' | '.join(tail))


def check_format(quick):
    if quick:
        record('formatação', SKIP, '--quick')
        return
    dart = str(Path(flutter_cmd()).parent /
               ('dart.bat' if os.name == 'nt' else 'dart'))
    code, out = run([dart, 'format', '--output=none',
                     '--set-exit-if-changed', 'lib', 'test', 'tool'], APP)
    last = out.strip().splitlines()[-1] if out.strip() else ''
    record('formatação', PASS if code == 0 else FAIL, last)


def check_analyze(quick):
    if quick:
        record('análise estática', SKIP, '--quick')
        return
    code, out = run([flutter_cmd(), 'analyze', '--fatal-infos'], APP)
    if code == 0 and 'No issues found' in out:
        record('análise estática', PASS, 'flutter analyze --fatal-infos limpo')
    else:
        tail = out.strip().splitlines()[-3:]
        record('análise estática', FAIL, ' | '.join(tail))


def check_tests(quick):
    if quick:
        record('testes', SKIP, '--quick')
        return
    code, out = run([flutter_cmd(), 'test'], APP)
    match = re.search(r'\+(\d+)(?: -\d+)?: All tests passed!', out)
    if code == 0 and match:
        record('testes', PASS, f'{match.group(1)} testes passaram')
    else:
        tail = out.strip().splitlines()[-3:]
        record('testes', FAIL, ' | '.join(tail))


def check_requirements_matrix():
    """Cruza a matriz de requisitos com o código: nomes citados têm de existir."""
    doc = (ROOT / 'docs/REQUIREMENTS.md').read_text(encoding='utf-8')
    test_text = '\n'.join(
        p.read_text(encoding='utf-8') for p in (APP / 'test').rglob('*.dart'))
    lib_text = '\n'.join(
        p.read_text(encoding='utf-8') for p in (APP / 'lib').rglob('*.dart'))

    bad = []
    # Nomes de teste citados entre crases que parecem frases de teste.
    for name in re.findall(r'`([a-z][^`]*?)\.\.\.`', doc):
        if name not in test_text:
            bad.append(f'teste "{name}"')
    # Arquivos de teste citados.
    for name in re.findall(r'`([a-z_]+_test\.dart)`', doc):
        if not list((APP / 'test').rglob(name)):
            bad.append(f'arquivo {name}')
    # Todo identificador camelCase entre crases precisa existir no código.
    # É a checagem mais ampla: pega função renomeada ou inventada.
    checked = 0
    for token in set(re.findall(r'`([A-Za-z][A-Za-z0-9]+)`', doc)):
        if token.islower() or token.isupper():
            continue
        if not re.search(r'[a-z][A-Z]', token):
            continue      # PascalCase de arquivo/formato, não símbolo
        checked += 1
        if token not in lib_text and token not in test_text:
            bad.append(f'símbolo {token}')

    if bad:
        record('matriz de requisitos', FAIL, f'citações sem lastro: {bad}')
    else:
        record('matriz de requisitos', PASS,
               f'{checked} identificadores e os testes citados existem')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--quick', action='store_true')
    args = parser.parse_args()

    if flutter_cmd() is None and not args.quick:
        record('toolchain', FAIL, 'flutter não encontrado; defina FLUTTER')
        return 1

    check_files()
    check_docs()
    check_requirements_matrix()
    check_code_rules()
    check_format(args.quick)
    check_analyze(args.quick)
    check_tests(args.quick)

    failed = [r for r in results if r[1] == FAIL]
    skipped = [r for r in results if r[1] == SKIP]
    print()
    print(f'{len(results) - len(failed) - len(skipped)} passaram, '
          f'{len(failed)} falharam, {len(skipped)} pulados')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

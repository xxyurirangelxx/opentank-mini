# Pesquisa de protocolo

Material bruto que fundamenta [docs/PROTOCOL.md](../docs/PROTOCOL.md) e
[docs/VALIDATION.md](../docs/VALIDATION.md). A maior parte foi produzida
instrumentando o editor oficial M-EFCS com Frida, sem alterar argumentos nem
retornos das chamadas.

## Conteúdo

| Pasta | O que tem |
|---|---|
| `captures/` | Logs `.jsonl` das chamadas WinMM do M-EFCS (`TX SYSEX`, `RX SYSEX`) |
| `dumps/` | Buffers lidos do pedal: AMP de 8 KB e CAB reconstruído dos uploads |
| `validation/` | Resultados das sondas Python e dos testes USB/BLE |
| `artifacts/` | Backups de referência e WAVs de teste |
| `fixtures/` | Backup de presets usado como vetor de teste |
| `screenshots/` | Capturas de tela do editor oficial durante a investigação |

## Ferramentas

As sondas Python ficam em [tools/research](../tools/research). Elas dependem de
`bleak`, `frida` e `pywinauto`, e várias apontam para caminhos absolutos da
máquina onde foram escritas. São scripts de investigação, não biblioteca.

| Script | Função |
|---|---|
| `probe_readonly.py` | Carrega só as definições de WinMM e consulta identidade/RAM |
| `validate_live.py` | Suíte reversível por USB: toggles, parâmetros, seleção |
| `validate_ble.py` | A mesma suíte pelo transporte BLE proprietário |
| `validate_codec.py` | Testa empacotamento 7 bits com 1000 casos |
| `capture_mefcs.py` | Instrumenta o M-EFCS com Frida e grava as chamadas MIDI |
| `decode_capture.py` | Decodifica uma captura e agrupa os comandos únicos |
| `tankbase.py` | Base comum: abrir portas, ler, escrever, commit, swap |

O núcleo do app em Dart tem equivalente mais limpo em
[app/tool/hil_probe.dart](../app/tool/hil_probe.dart), que exercita o mesmo
código de produção diretamente contra o pedal. Prefira ele.

## Reproduzir uma captura

```bash
# 1. abrir o editor oficial normalmente
# 2. anexar o capturador ao processo já aberto
python tools/research/capture_mefcs.py --attach
# 3. executar a ação no editor
# 4. fechar a captura e decodificar
python tools/research/decode_capture.py research/captures/capture-mefcs-XXXX.jsonl
```

Anexar a um processo já aberto é obrigatório: ao abrir o app pelo capturador, o
hook instala em `WINMM.dll` enquanto o editor resolve as funções por
`winmmbase.dll`, e nenhuma chamada é vista.

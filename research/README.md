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
| `capture_blocked.py` | Captura comandos **sem entregá-los** ao pedal (restore/erase) |
| `decode_capture.py` | Decodifica uma captura e agrupa os comandos únicos |
| `read_model_flash.py` | Lê os 245760 bytes da flash de modelos em `0x70000000` |
| `read_model_names.py` | Lê as tabelas de nomes de AMP (`0x90`) e CAB (`0x80`) |
| `map_model_flash.py` | Confirma o mapa índice-do-preset → endereço na flash |
| `audit_model_flash.py` | Compara os 30 blocos da flash com a imagem de fábrica |
| `test_model_flash_write.py` | Grava um registro alterado, confere e restaura |
| `restore_model_block.py` | Restaura um bloco da flash a partir do backup |
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

## Descobrir comandos destrutivos sem executá-los

`capture_blocked.py` intercepta `midiOutLongMsg` e devolve sucesso **sem chamar
a função original**. O editor acredita ter enviado; o pedal não recebe nada.
Foi assim que o "Restore AM4 Amp/Cab" do M-EFCS foi decifrado sem apagar a
flash do pedal:

```bash
# com o editor aberto e conectado ao pedal
python tools/research/capture_blocked.py --seconds 600
# clique em More → Factory Restore → Restore ... e confirme
```

As capturas resultantes estão em `captures/capture-blocked-*.jsonl` e o
conteúdo enviado foi reconstruído em `dumps/factory-am4-buffer.bin`. Ele bate
byte a byte com a leitura da região `0x70000000` do pedal
(`dumps/models-70000000.bin`), o que comprova o mapa sem nenhuma escrita.

## Dados que servem de vetor de teste

| Arquivo | Conteúdo |
|---|---|
| `dumps/factory-am4-buffer.bin` | 245760 bytes da flash de modelos de fábrica |
| `dumps/models-70000000.bin` | cópia lida do pedal (idêntica à de cima) |
| `dumps/model-names.json` | 20 nomes de AMP e 20 de CAB |
| `fixtures/factory-bank-am4.bin` | 21 presets de fábrica (1932 bytes) |
| `fixtures/Tank Mini_AllPresets.atkm` | banco do usuário usado nos testes |

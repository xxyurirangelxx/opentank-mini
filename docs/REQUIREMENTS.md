# Requisitos e evidência

Matriz do que foi pedido, onde está implementado, qual teste cobre e o que foi
comprovado contra o pedal. **Nenhuma linha aqui é "pronto" sem código e teste
nomeados.** O que falta está marcado.

Legenda da coluna *Pedal*:

- **sim** — exercitado contra `TANK MINI_009`, com releitura.
- **indireto** — o protocolo foi validado por sonda, mas o app ainda não rodou
  nesse caminho contra o pedal.
- **não** — não testado.

## Funções do M-EFCS

| Requisito | Código | Teste | Pedal |
|---|---|---|---|
| Ler os 21 slots | `TankDevice.readSlot` | `tank_device_test.dart` | sim |
| Ler o preset ativo | `TankDevice.readActive` | idem | sim |
| Editar volume | `TankController.apply` + `setVolume` | `tank_controller_test.dart` | sim |
| Editar routing (6 blocos) | `setRouting` | idem | sim |
| Ligar/desligar bloco | `setBlockEnabled` | idem | sim |
| Trocar modelo de bloco | `setBlockModel` | idem | sim |
| Mostrar nome de AMP e CAB na interface | `TankDevice.readModelNames` + `ModelNames` | `le os nomes de AMP e CAB na area de modelo`, `traz os nomes de AMP e CAB que o pedal reporta` | sim (20 + 20 nomes, 0 divergências contra 40 cabeçalhos) |
| Mostrar nome de FX, MOD, DLY e REV | `model_catalog.dart` (`catalogModelName`) | `model_catalog_test.dart` | indireto (o pedal não expõe; nomes do M-EFCS) |
| Nomear os knobs conforme o modelo | `parameterLabelsFor` | `model_catalog_test.dart` | indireto (rótulos do M-EFCS) |
| Faixa dos knobs do CAB | `parameterText` | `model_catalog_test.dart` | indireto (20–300 Hz e 18,0k–5,0k) |
| Editar parâmetros | `setParameter` | idem | sim |
| Pré-ouvir antes de salvar | `apply` grava na RAM | `editar aplica no pedal...` | sim |
| Salvar no slot atual | `save` → `saveSlot` | `save grava no slot...` | sim |
| Salvar em outro slot | `saveTo` | `saveTo grava em outro slot sem mudar o ativo` | sim |
| Trocar dois slots | `swapSlots` | `swap troca dois slots no banco e na flash` | sim |
| Descartar alteração não salva | `revert` | `revert descarta o rascunho` | sim |
| Importar AMP e pré-ouvir | `encodeAmp` + `uploadModel` | `uploadModel fatia em 1015 bytes...` | sim |
| Importar CAB e pré-ouvir | `encodeCab` + `WavFile` + `uploadModel` | `wav_model_test.dart` | sim |
| Gravar AMP permanentemente | `encodeAmpFlashRecord` + `writeModelFlash` | `model_flash_test.dart`, `tank_device_test.dart` | sim |
| Gravar CAB permanentemente | `encodeCabFlashRecord` + `writeModelFlash` | idem | sim |
| Afinador | `setTuner` | `tank_controller_test.dart` | sim (byte 3 de `0x70100000`) |
| Loopback | `setLoopback` | idem | ACK aceito; sem reflexo no estado global |
| Bypass | `setBypass` | idem | sim (byte 2 de `0x20000000`) |
| Backup/restauração do banco | `PresetBank` + `restoreBank` | `preset_bank_test.dart` | sim |
| Backup/restauração de modelos | `readModelFlashAll` + `restoreModelFlashAll` | `tank_controller_test.dart` | sim |

## Plataformas

| Requisito | Código | Build | Pedal |
|---|---|---|---|
| Windows USB MIDI | `midi_transport.dart` | `opentank_mini.exe` compila e roda | sim (conexão e leitura dos 21 slots) |
| Windows BLE | `ble_transport.dart` | idem | não |
| Linux USB MIDI | idem | CI (`build-linux`) | não |
| Linux BLE | idem | CI | não |
| Android BLE | `ble_transport.dart` | APK compila (46,6 MB) | não |

O transporte USB e o BLE **foram** validados contra o pedal pelas sondas Python
(`validate_live.py`, `validate_ble.py`), que usam o mesmo protocolo e o mesmo
empacotamento. O que não rodou foi o binário Flutter nesses caminhos.

## Escalabilidade

| Requisito | Situação |
|---|---|
| Camadas separadas para IA e normalização | `core/` não conhece Flutter; `TankDevice` recebe um `TankTransport` por injeção. Um módulo de normalização entra como função de `core/model` |
| Sem estado global | tudo passa pelo `TankController` injetado |
| Testável sem hardware | `FakeTransport` em `test/support`; 103 testes rodam sem pedal |

## O que não está pronto

| Item | Por quê |
|---|---|
| Persistência após power-cycle | a gravação não leva commit e ainda não houve desligar/ligar |
| Nomes de FX, MOD, DLY e REV | vêm do catálogo do M-EFCS, não do pedal: varrendo `0x80000000`..`0xA0000000` só existem as tabelas de AMP e CAB |
| Áudio (afinador, loopback, bypass) | precisa de guitarra e ouvido |
| Número de amostras que o CAB usa na flash | IR de fábrica curto não revela; ver `PROTOCOL.md` |

Para conferir mecanicamente o que está listado como pronto:

```bash
python tools/verify_repo.py
```

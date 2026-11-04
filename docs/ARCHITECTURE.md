# Arquitetura

## Princípio

Tudo que não é transporte precisa ser testável sem pedal. O protocolo é
suficientemente chato (bytes, checksum, limites de tamanho) para que testar com
hardware em toda mudança seja inviável; por isso o código é fatiado em camadas
com uma fronteira única, o `TankTransport`.

```
UI (Flutter)
   ↓
TankController          estado da sessão, rascunho, operações de negócio
   ↓
TankDevice              tradução para mensagens, validação de respostas
   ↓
TankTransport           MIDI nativo  |  BLE proprietário
   ↓
Pedal
```

## Camadas

### `core/protocol`

- `packing.dart` — empacotamento contínuo de 8 para 7 bits e frames SysEx.
- `messages.dart` — construção de cada mensagem, endereços, áreas e checksum.

Sem dependências além de `dart:typed_data`. É a camada com mais testes, porque um
erro aqui corrompe dados no aparelho.

### `core/model`

- `preset.dart` — o preset de 92 bytes como objeto imutável. Alterar devolve um
  novo preset, o que torna trivial descartar um rascunho e comparar com o salvo.
- `preset_bank.dart` — leitura e escrita do `.atkm` (21 × 92 + `PATCHEND\0\0`).
- `model_format.dart` — buffers de AMP (`AM2\0`) e CAB (`CAB\0`).

### `core/device`

`TankDevice` expõe operações de negócio (`readSlot`, `saveSlot`, `swapSlots`,
`uploadModel`, toggles globais) e cuida de:

- serializar conversas, porque o protocolo não tem ID de correlação;
- fatiar leituras em 431 bytes e escritas em 1015 bytes;
- validar checksum e distinguir ACK de NAK;
- esperar a RAM convergir depois de trocar de preset;
- conferir por releitura o que acabou de escrever.

### `core/transport`

Uma interface de quatro membros. Nada acima dela sabe se o link é USB ou BLE.

### `platform`

- `midi_transport.dart` — `flutter_midi_command`; empacota em SysEx.
- `ble_transport.dart` — `universal_ble`; fala o transporte proprietário em
  AE40/AE41/AE42, fragmentando pelo MTU e remontando as respostas.

Detalhe importante: no BLE o payload trafega **sem** `F0`/`F7` e **sem**
empacotamento de 7 bits. A conversão é responsabilidade do transporte, para que
o `TankDevice` veja sempre a mesma coisa.

### `state` e `ui`

`TankController` é um `ChangeNotifier` com o banco lido, o slot ativo e o
rascunho. A regra central: editar aplica no pedal em tempo real (RAM), mas não
grava na flash até o usuário pedir Save. `isDirty` compara rascunho e slot salvo.

## Decisões

**Por que Flutter.** Windows, Linux e Android com MIDI e BLE exigem uma matriz
que só o Flutter cobre hoje com plugins mantidos: `flutter_midi_command` tem
implementação nativa para os três desktops e para Android, e `universal_ble`
cobre Windows e Android. Tauri v2 não tem BLE maduro no Android.

**Por que o preset é imutável.** Facilita desfazer, comparar e evitar que uma
edição parcial deixe o estado inconsistente.

**Por que ler tudo e conferir.** O protocolo não tem transação nem número de
sequência. A única garantia de que a escrita funcionou é reler.

## Limitações de projeto

- Sem ID de mensagem: uma conversa por vez. Requisições concorrentes lançam
  erro em vez de se misturar.
- Sem retry automático: uma falha vira exceção tipada e a UI decide.
- Timeout curto por padrão (3 s), ajustável por operação.

## Próximos passos previstos

1. Nomes dos modelos de todos os blocos, a partir de enumeração no aparelho.
2. Gravação permanente de AMP/CAB, quando o comando for descoberto.
3. Afinador com leitura de frequência.
4. Normalização de volume entre presets.
5. Integrações de IA para sugestão de cadeia.

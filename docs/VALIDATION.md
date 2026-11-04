# Validação contra hardware

Registro do que foi de fato verificado contra a Tank Mini, o que foi verificado
apenas em software e o que continua em aberto. A regra deste documento: se não
há evidência, não é "pronto".

Aparelho usado: `TANK MINI_009`, firmware reportado como versão 9, USB
`4C4A:C755`, BLE `TANK MINI_BLE`. Sistema de teste: Windows 10 Pro 19045.

## Verificado contra o hardware

| Operação | Método | Resultado |
|---|---|---|
| Identificação | leitura via WinMM | retorna `TANK MINI`, versão 9 |
| Leitura dos 21 slots | comparada byte a byte com backup do M-EFCS | 21/21 idênticos |
| Leitura do preset ativo | comparação com o slot correspondente | idêntica |
| Escrita de preset + commit | gravação em slot sacrificial, releitura | idêntica ao gravado |
| Restauração após escrita | reescrita do original, releitura | idêntica ao backup |
| Swap entre dois slots | troca, verificação, troca inversa | confirmado, restaurado |
| Seleção de slot | com espera de convergência da RAM | converge em 1–2 leituras |
| Banco completo após todos os testes | SHA-256 do dump contra o backup | idêntico |
| Descartar alteração não salva | mudar volume na RAM, reescrever o valor salvo | RAM volta ao slot |
| Leitura de bloco grande | 8192 bytes em fatias de 431 | estável entre leituras |
| Escrita de bloco grande | 1015 bytes por comando | ACK e conteúdo confere |
| Flash de modelos `0x70000000` | 245760 bytes lidos e comparados com a captura | idêntica (SHA-256) |
| Tabelas de nomes de AMP e CAB em `0x80`/`0x90` | leitura | 20 nomes de cada |
| Gravação permanente de AMP | registro alterado gravado, relido e restaurado | persiste sem commit |
| Integridade após os testes | auditoria dos 30 blocos contra a captura | 30/30 idênticos |

O dump completo foi refeito ao final da bateria de testes e bateu com o backup
original: SHA-256 `08b87ad4…29ac`.

### Fluxos capturados do editor oficial

O M-EFCS foi instrumentado com Frida para registrar as chamadas de MIDI sem
alterar argumentos nem retornos. As capturas ficam em `research/captures/`.

| Ação | Capturado |
|---|---|
| Bypass on/off | sim |
| Loopback on/off | sim |
| Afinador on/off e consulta | sim |
| Volume do preset | sim |
| Save no slot atual | sim |
| Save to em outro slot | sim |
| Swap entre slots (composto) | sim |
| Routing da cadeia | sim, com restauração |
| Preview de AMP (upload + ativação) | sim |
| Preview de CAB (upload + ativação) | sim |
| Restore de presets AM4 (banco de fábrica) | sim, sem executar no pedal |
| Restore de Amp/Cab (apagar setor + escrita) | sim, sem executar no pedal |

### Captura sem execução

O "Restore AM4 Amp/Cab" do editor é a única forma de descobrir a gravação
permanente de modelos, mas executá-lo apaga a flash do pedal. A solução foi
interceptar `midiOutLongMsg` com Frida e devolver sucesso **sem chamar a
função original** (`tools/research/capture_blocked.py`): o editor acredita ter
enviado, o pedal não recebe nada.

O resultado: 307 comandos únicos capturados, com o buffer completo de 30
modelos (245760 bytes). A leitura da região `0x70000000` do pedal devolveu o
**mesmo SHA-256** (`9e8fc4e7…3d82`) do que o editor enviou, o que confirma que
o mapa endereço↔conteúdo está correto sem ter precisado apagar nada.

## Verificado só em software

- Empacotamento de 7 bits: 1000 casos pseudoaleatórios de 7 a 512 bytes.
- Checksum em todos os 382 frames capturados.
- Todas as mensagens do protocolo comparadas com capturas reais.
- Leitura de WAV PCM 16/24 bits, mono e estéreo.
- Formato `.atkm` com o backup real de 1942 bytes.

## Não verificado

| Item | Por que |
|---|---|
| Persistência após desligar o pedal | exige desligar e religar o aparelho |
| Gravação permanente de AMP/CAB após power-cycle | o comando está decifrado e conferido por releitura; falta desligar/ligar |
| Afinador com sinal de áudio | precisa de guitarra e ouvido humano |
| Loopback e bypass audíveis | precisa de áudio |
| Linux USB e BLE | sem máquina Linux disponível |
| Android BLE | sem aparelho para instalar o APK |
| Todos os modelos de todos os blocos | só uma transição por bloco foi testada |
| Build Windows do app | Visual Studio sem os componentes C++; instalação exige UAC |

## Falhas conhecidas do editor oficial

Reproduzidas durante a investigação e úteis para justificar este projeto:

1. **Crash ao salvar CAB.** `errorToast` chama `Overlay.of(context)` com um
   contexto inválido e derruba o processo:
   `Null check operator used on a null value` em `import_cab.dart:157`.
   Consequência: a gravação permanente de CAB nunca foi observada.
2. **Porta MIDI presa.** Se o app cai, a porta fica ocupada e as tentativas
   seguintes falham com `MMSYSERR_NOMEM` até o processo morrer de vez.
3. **Lista de CAB vazia sem aviso.** Arquivos de 24 bits não aparecem na lista
   em alguns casos, sem mensagem de erro.

## Como reproduzir

```bash
cd app
flutter test                      # suíte sem hardware
dart run tool/hil_probe.dart      # leitura contra o pedal
dart run tool/hil_probe.dart --write-test --swap-test   # escrita e swap
```

O `hil_probe` fala WinMM por FFI e exercita o mesmo núcleo Dart que o app usa,
inclusive `TankDevice`, checksum e empacotamento.

# Validação do protocolo Tank Mini

Data: 2026-11-04. Hardware identificado: `TANK MINI_009`.
Host: Windows. Sondas temporárias de investigação; não constituem o app nem uma biblioteca de produção.

## Situação

A suíte reversível implementada passou em USB e BLE. A validação integral do substituto do M-EFCS NÃO está concluída: gravação, swap, transferências de AMP/CAB e controles globais ainda dependem de descoberta/captura de protocolo. Linux e Android não foram testados.

Nenhum comando de save flash, upload AMP/CAB ou reset foi enviado. O estado final ativo foi restaurado ao 2B e conferido byte a byte.

## Evidências

- USB: `validation-live-20261104-164947.json`.
- BLE: `validation-ble-20261104-165025.json`.
- Auditoria reproduzível: `audit_validation.py`.
- Backup original: `Tank Mini_AllPresets.atkm`.
- Banco reconstruído de 21 leituras USB após seleção: `validated-usb-readback.atkm`.
- Os dois bancos têm 1942 bytes e SHA-256 `08b87ad485f2e6bef2c831db8fd2e54afd878864e53dd6d6bd51e8099cf829ac`.
- Snapshot ativo restaurado: `snapshot-active-ram.tkm`, 92 bytes, SHA-256 `5e82443b124c04a0a499b8c41f507a235c30d5d6ba6b48a3c025822ef6e1376a`.

## Resultados físicos

| Capacidade | USB no Windows | BLE no Windows | Limite da evidência |
|---|---|---|---|
| Identificação e checksum | PASS | PASS | Firmware observado 009 |
| Leitura dos 92 bytes ativos | PASS | PASS | RAM, não leitura flash arbitrária |
| Seleção e leitura dos 21 presets | PASS | PASS | Todos idênticos ao backup; seleção muda preset ativo |
| Toggle de seis blocos | PASS | PASS | Alteração e restauração verificadas por leitura |
| Escrita em 30 endereços de parâmetros | PASS | PASS | Um valor vizinho por endereço no preset 2B; não todos os tipos, faixas ou significado sonoro |
| Seleção de modelo/slot de seis blocos | PASS | PASS | Uma transição por bloco; não inventário completo dos modelos |
| Descarte de preview ao sair e voltar | PASS | PASS | Testado com alteração de gain AMP sem save |
| Restauração final | PASS | PASS | 92 bytes idênticos ao estado inicial |

### Mapa observado

- Toggles: endereços/offsets FX=8, AMP=9, MOD=10, DLY=11, REV=12, CAB=13.
- Seletores: FX=14, AMP=15, MOD=16, DLY=17, REV=18, CAB=19.
- Parâmetros verificados: FX 20/22/24/26; AMP 32/34/36/38/40; MOD 44/46/48/50/52/54; DLY 56/58/60/62/64/66; REV 68/70/72/74/76/78; CAB 80/82/84.
- O mapa offline anterior que associa CAB=12 e REV=13 contradiz este hardware. Não alterar o projeto anterior automaticamente; transportar o mapa com fixtures verificadas para o app novo.
- Selecionar modelos FX/MOD/DLY/REV pode também modificar parâmetros. As listas de diferenças estão nos logs; o app deve reler o bloco, não atualizar somente seu ID. No BLE, uma leitura logo após ACK pode ainda não refletir todas as mudanças secundárias.

### USB

- VID/PID observado: `4C4A:C755`, interface MIDI `MI_03`.
- Portas observadas nesta sessão: IN 0 e OUT 1, ambas `USB-Midi`.
- Índices NÃO são identificadores estáveis. A sonda usa índices fixos e não é adequada para uso de produção.
- Payload lógico empacotado 8→7 bits em SysEx F0/F7.

### BLE

- Descoberta por nome encontrou `TANK MINI_BLE`.
- Serviço usado e enumerado: `0000ae40-0000-1000-8000-00805f9b34fb`.
- TX `ae41`: write without response; RX `ae42`: notify.
- Dados lógicos raw, sem packing SysEx.
- MTU observado pelo cliente Windows: 517; não assumir esse valor em outros hosts.
- Advertisement expôs o UUID BLE-MIDI `03b80e5a-ede8-4b33-a751-6ce34ec4c700`, e esse serviço também apareceu no GATT. Portanto, é incorreto afirmar ausência de BLE-MIDI. Contudo, sua funcionalidade não foi testada; o controle proprietário AE40 foi o caminho validado.
- MAC observado é endereço de uma unidade; não hardcodar no app.
- ACK não implica convergência: execução inicial leu 1A ao pedir 1B. O teste passou depois de aguardar leituras correspondentes ao destino, com timeout de 3 segundos. Várias trocas exigiram duas leituras. Em produção não haverá backup prévio do destino para fazer esse predicado; é necessário projetar confirmação por eventos/identidade e estabilidade do estado.

## Testes offline e falhas encontradas

`validate_codec.py` exercitou 100 payloads em cada um de dez tamanhos (1000 casos). A recuperação independente do payload passou em todos. O encoder legado acrescenta padding zero não canônico em tamanho 7, mas a consulta real de identidade usando esse formato foi aceita. Não corrigir arbitrariamente o formato transmitido sem testar a compatibilidade física.

Houve uma execução da sonda USB interrompida por `NameError` na geração da lista de parâmetros; a iteração foi corrigida e a suíte completa foi repetida. Houve uma falha BLE por leitura prematura após ACK, preservada no log anterior. Os logs finais não contêm resultados FAIL.

Não foram executados testes de áudio, limites 0/100 de todos os controles, todos os modelos, fragmentação em MTU pequeno, desconexão forçada, reconexão sob falha ou reinicialização física. Não extrapolar os PASS para esses cenários.

## Pendências bloqueadas

| Item | Bloqueio | Evidência necessária |
|---|---|---|
| Save e save to | Pacote `00 59 22 64` existe somente em documentação anterior, sem TX capturado | Capturar ação oficial, validar endereçamento, salvar valor diferente em slot controlado, reler, trocar preset e reiniciar fisicamente |
| Swap | Sem comando observado | Captura oficial e comparação antes/depois dos dois slots e do banco |
| AMP/CAB: importar, audition, commit | Sem protocolo de transferência; ATKM não contém os blobs | Capturar arquivo/tamanho/chunks/checksum/finalização; preservar modelos que seriam sobrescritos |
| Afinador | Sem comando ou eventos conhecidos | Capturar ativação/desativação e dados de nota/frequência |
| Loopback | Sem comando conhecido | Capturar configuração oficial e validar roteamento por áudio |
| Bypass global | Toggles por bloco não provam equivalência | Capturar ação oficial, observar parâmetros e áudio |
| Routing | Apenas proposta documental contraditória | Capturar uma mudança reversível e comparar estado |
| Volume global do preset | Offset 0 sugerido, comando não confirmado | Captura oficial e leitura diferencial |
| Linux e Android | Sem execução nesses hosts nesta sessão | Repetir testes físicos nos sistemas-alvo; Android somente BLE |

A verificação inicial de ferramentas no PATH não encontrou `tshark`, `dumpcap`, `USBPcapCMD` ou `frida`. Depois, Frida 17.25.2 e ferramentas de inspeção de UI foram instaladas no ambiente isolado `.venv-validation`. O executável atual foi localizado em `C:\Users\Yuri Rangel\Downloads\M-EFCS\m_efcs.exe`; uma cópia foi isolada em `capture-input/m-efcs`. A autorização explícita foi recebida posteriormente. A primeira execução autorizada criou a cópia de teste PID 32908, mas Frida 17.25.2 abortou com `Unable to locate the ntdll loader TLS routines` antes de retomar o editor; não houve captura de comandos. Caminho, processo pai 12988 e horário de criação foram verificados antes de encerrar essa cópia suspensa. Frida foi substituído por 16.7.19 no ambiente isolado para testar compatibilidade, ainda não comprovada. A nova tentativa foi bloqueada novamente pelo classificador, apesar da autorização recebida. Não contornar essa negativa por outra ferramenta. A captura oficial permanece bloqueada pela permissão de execução.

## Próxima etapa necessária

Obter autorização explícita para executar a cópia do M-EFCS de Downloads e a captura local de suas chamadas MIDI/USB. Capturar uma operação por vez, incluindo baseline, ação, TX/RX e exportação posterior. Começar por routing, afinador, loopback e bypass; deixar gravação e upload por último. Só então implementar/repetir os testes faltantes. O objetivo integral permanece pendente, não aprovado implicitamente pelos testes parciais.

## Execução das sondas

As sondas `validate_live.py` e `validate_ble.py` alteram estado temporário e restauram o 2B identificado pelo backup. Não executá-las com outra unidade, portas diferentes, outro firmware ou estado não salvo sem revisar suas pré-condições. A restauração depende de conexão operacional; falhas físicas podem impedir cleanup. O backend WinMM herdado tem espera de envio sem timeout interno; o timeout do processo não é garantia de rollback.

Ambiente BLE isolado: `.venv-validation`, com Bleak 3.0.2. Nenhum projeto Flutter/Tauri foi criado.

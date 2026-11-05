# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento semântico.

## [0.1.1] — 2026-11-05

### Corrigido

- **Ícones vazios na interface.** O Flutter reduzia a fonte de ícones a um
  subconjunto e reaproveitava esse subconjunto do cache, que não era
  invalidado quando a interface mudava. O build agora usa
  `--no-tree-shake-icons` e empacota a fonte completa.
- **Acentuação.** O app empacota Roboto (regular, medium e bold) e todos os
  textos de tela passaram a usar acentuação correta.
- **Menu lateral** com alinhamento e largura consistentes entre logo e itens.
- **Lista de modelos** com altura fixa, sem esticar a linha no cartão.

### Adicionado

- Instalador para Windows (`dist/OpenTankMini-<versão>-windows-x64.exe`),
  por usuário, sem exigir administrador. Gerado por
  `python tools/build_installer.py`.
- `docs/BRANDING.md` com o prompt de identidade visual e o passo a passo
  para aplicar a logo no app e no instalador.

## [0.1.0] — 2026-11-04

Primeira versão utilizável. Substitui o M-EFCS nas funções de edição de preset.

### Adicionado

- Leitura dos 21 slots e do preset ativo.
- Edição de volume, routing, liga/desliga, modelo e parâmetros por bloco.
- Preview em tempo real na RAM, com descarte sem gravar.
- Save no slot atual, Save to e Swap entre dois slots.
- Bypass, loopback e afinador como toggles globais.
- Importação de AMP (`.am2Data`) e CAB (`.wav`), enviados ao buffer de modelo do
  pedal com prévia, e **gravação permanente em qualquer um dos 20 slots**.
- Exportação e restauração do banco completo (`.atkm`).
- Nomes de AMP e CAB nas listas suspensas, lidos do pedal a cada conexão.
- Transportes USB MIDI (Windows/Linux/Android) e BLE proprietário.
- Núcleo em Dart puro com 112 testes, incluindo vetores extraídos de capturas
  reais do editor oficial.

### Descoberto

- O checksum do protocolo começa no índice 5, não no 4.
- O endereço dos comandos de tempo real é `0x10000000 + offset`.
- O buffer de modelo em `area 0x05` começa com `AM2\0` (AMP) ou `CAB\0` (CAB).
- O CAB é armazenado como 2048 amostras PCM 24-bit e o firmware normaliza o IR.
- O M-EFCS 3.10.1017 derruba o processo ao tentar salvar CAB.
- A flash de modelos fica em `0x70000000` (245760 bytes), com 20 AMPs de 8192
  bytes e 20 CABs de 4096. O comando `0x21` apaga um setor de 4 KB.
- **A gravação de modelo não leva commit**: enviar o commit `F0` com
  `area 0x05` faz o pedal descartar o bloco inteiro.
- Nomes de fábrica dos 20 AMPs e 20 CABs, lidos das tabelas `0x90`/`0x80`.
- As tabelas de nomes usam registros de 14 bytes e são **vivas**: gravar um
  modelo troca o nome na hora. É delas que a interface tira os nomes das listas
  suspensas — nada de lista fixa no código.
- FX, MOD, DLY e REV não têm tabela de nomes no pedal; a interface mostra o
  número do modelo.
- O preset guarda o índice do modelo **0-based**: `0` é o primeiro modelo. Nos
  21 presets de fábrica o maior valor de cada bloco é exatamente `contagem - 1`,
  e há presets com FX `0` e o FX ligado — logo `0` é o Noise gate, não "sem
  modelo".
- Nomes e parâmetros de FX, MOD, DLY e REV vêm do catálogo do editor oficial
  (o pedal não guarda esses nomes), com os rótulos por modelo.
- O CAB mostra Low Cut (20–300 Hz) e High Cut (18,0k–5,0k) em vez de 0..100.

### Limitações conhecidas

- Persistência após desligar o pedal ainda não testada.
- Linux e Android sem teste em hardware real.


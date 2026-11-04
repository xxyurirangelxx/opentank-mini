# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento semântico.

## [0.1.0] — 2026-11-04

Primeira versão utilizável. Substitui o M-EFCS nas funções de edição de preset.

### Adicionado

- Leitura dos 21 slots e do preset ativo.
- Edição de volume, routing, liga/desliga, modelo e parâmetros por bloco.
- Preview em tempo real na RAM, com descarte sem gravar.
- Save no slot atual, Save to e Swap entre dois slots.
- Bypass, loopback e afinador como toggles globais.
- Importação de AMP (`.am2Data`) e CAB (`.wav`), enviados ao buffer de modelo do
  pedal com prévia.
- Exportação e restauração do banco completo (`.atkm`).
- Transportes USB MIDI (Windows/Linux/Android) e BLE proprietário.
- Núcleo em Dart puro com 65 testes, incluindo vetores extraídos de capturas
  reais do editor oficial.

### Descoberto

- O checksum do protocolo começa no índice 5, não no 4.
- O endereço dos comandos de tempo real é `0x10000000 + offset`.
- O buffer de modelo em `area 0x05` começa com `AM2\0` (AMP) ou `CAB\0` (CAB).
- O CAB é armazenado como 2048 amostras PCM 24-bit e o firmware normaliza o IR.
- O M-EFCS 3.10.1017 derruba o processo ao tentar salvar CAB.

### Limitações conhecidas

- Gravação permanente de AMP/CAB não implementada: o comando não foi capturado.
- Nomes de modelo só para o bloco FX.
- Linux e Android sem teste em hardware real.

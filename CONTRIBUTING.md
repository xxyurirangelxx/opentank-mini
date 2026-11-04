# Contribuindo

Obrigado pelo interesse. Este projeto é sobre hardware de terceiros, então a
regra principal é: **não quebre o pedal de ninguém**.

## Antes de abrir um PR

1. `cd app && flutter test` precisa passar.
2. `flutter analyze` precisa estar sem erros.
3. Se mexer no protocolo, inclua a evidência: um frame capturado, um dump, ou um
   teste com vetor real.

## Boas contribuições

- Capturas de protocolo com contexto: qual botão, qual firmware, o que mudou.
- Nomes dos modelos de cada bloco — os de AMP e CAB já estão em
  `research/dumps/model-names.json`; faltam FX, MOD, DLY e REV.
- Testes que reproduzam um bug antes de corrigi-lo.
- Suporte verificado a Linux e Android.
- Confirmação de que a gravação de modelo sobrevive ao power-cycle.

## Protocolo

Leia [docs/PROTOCOL.md](docs/PROTOCOL.md) antes de propor mudanças. Os pontos
mais fáceis de errar:

- O checksum começa no índice 5, não no 4.
- O endereço dos comandos de tempo real é `0x10000000 + offset`.
- Leitura tem teto de 431 bytes; escrita, 1015.
- No BLE o payload vai cru, sem `F0`/`F7` e sem empacotamento de 7 bits.
- A flash de modelos (`0x70000000`) se grava com `0x21` (apaga setor) e `0x22`,
  **sem commit**: um commit `F0` em `area 0x05` descarta o bloco.

## Testes com hardware

Sempre tire um dump do banco antes:

```bash
dart run tool/hil_probe.dart            # só leitura
```

Para operações destrutivas, use um slot sacrificial e restaure no mesmo teste.
O `hil_probe` já faz isso ao receber `--write-test`, `--swap-test`,
`--model-test` e `--flash-test` (este último faz backup de tudo, altera um byte,
restaura e audita os 30 blocos).

Depois de qualquer sessão em que o M-EFCS foi instrumentado, confira que o
pedal ficou intacto:

```bash
python tools/research/audit_model_flash.py    # 30 blocos contra a captura
```

## Estilo

- Dart formatado (`dart format .`).
- Comentários explicam *por quê*, não *o quê*.
- Nada de dependência nova sem justificativa no PR.

## Licença

Ao contribuir você concorda em licenciar sob a MIT.

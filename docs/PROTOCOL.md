# Protocolo da M-VAVE Tank Mini (TANK MINI v9)

Documento vivo. Cada comando abaixo foi **verificado fisicamente** contra o
dispositivo `TANK MINI_009` (USB `4C4A:C755`, BLE `TANK MINI_BLE`), salvo onde
marcado como não verificado. Capturas originais em `research/captures/`.

## 1. Enquadramento

### USB (WinMM / class-compliant MIDI)

O dispositivo usa SysEx proprietário entre `F0` e `F7`. O conteúdo é um
empacotamento contínuo de 8 para 7 bits, little-endian, sem escape:

```
acumula bits a cada byte de 7 bits; extrai um byte sempre que há 8 bits
```

O último grupo é preenchido com zeros. O frame SysEx de uma mensagem de `N`
bytes tem `ceil(N * 8 / 7) + 2` bytes.

### BLE (transporte proprietário)

Serviço `0000ae40-0000-1000-8000-00805f9b34fb`

| Papel | UUID | Propriedade |
|---|---|---|
| TX (host → pedal) | `0000ae41-...` | write without response |
| RX (pedal → host) | `0000ae42-...` | notify |

No BLE o payload sai **cru**, sem `F0`/`F7` e sem empacotamento 7 bits.
Também existe serviço BLE-MIDI padrão no advertisement
(`03b80e5a-ede8-4b33-a751-6ce34ec4c700`), não utilizado por este protocolo.

## 2. Mensagem

```
00 59 <cmd> <len LE16> <00> <area> <campos...> <checksum>
```

- `len` = tamanho do payload + 8 (para escritas) ou constante por comando.
- `area`: `0x04` = presets, `0x05` = buffer de modelo (AMP/CAB).
- `checksum` = `(255 - sum(bytes[5:-1])) % 256`.

O checksum **começa no índice 5**, não no 4. Isso importa: com payload acima de
247 bytes o campo `len` transborda para o índice 4, e calcular a partir do 4
produz checksum inválido. Esse foi o erro que limitava as escritas a 247 bytes.

Validação de resposta: `(255 - sum(resposta[5:-1])) % 256 == resposta[-1]`.

## 3. Comandos

### Identificação

```
TX 00 59 11 00 00 00 FF
RX nome do dispositivo + versão
```

### Leitura

```
00 59 23 08 00 00 <area> <addr LE32> <len LE16> 00 <cs>
```

- `addr = 0x00000000 + 92*slot` → flash do slot `slot` (0..20)
- `addr = 0x10000000` → RAM (preset ativo, 92 bytes)
- `area = 0x05`, `addr = 0` → buffer de modelo, 8192 bytes

Resposta:

```
00 59 23 <len LE16> 00 <area> <addr LE32> <len LE16> 00 <payload> <cs>
```

Limite de **431 bytes por leitura** (resposta SysEx de 512 bytes). Para blocos
maiores, fatiar. Endereço inválido responde `00 59 00 01 00 00 01 FE`.

### Escrita

```
00 59 22 <len+8 LE16> 00 <area> <addr LE32> <len LE16> 00 <payload> <cs>
```

ACK: `00 59 00 01 00 00 00 FF`. Escritas de até 1015 bytes verificadas.

### Commit (finaliza a gravação na flash)

```
00 59 22 08 00 00 04 00 00 00 F0 00 00 00 0B
```

Sem commit, a escrita fica no buffer e não persiste. O editor envia commit
imediatamente após cada gravação de preset.

### Seleção de preset

```
00 59 22 09 00 00 04 <slot> 00 00 E0 01 00 00 01 <cs>
```

A troca é assíncrona: a RAM pode devolver o preset anterior por algumas
dezenas de milissegundos. Sempre confirmar por releitura até convergir.

### Toggle de módulo

```
00 59 22 09 00 00 04 <endereço> 00 00 10 01 00 00 <valor> <cs>
```

Endereços: FX=8, AMP=9, MOD=10, DLY=11, REV=12, CAB=13.
Também é o comando usado para **selecionar modelo** (mesmo endereço, valor =
índice do modelo).

### Parâmetro (knob)

```
00 59 22 0A 00 00 04 <endereço> 00 00 10 02 00 00 <valor> 00 <cs>
```

Parâmetros são `uint16` little-endian, faixa 0..100.

### Routing da cadeia

```
00 59 22 0E 00 00 04 02 00 00 10 06 00 00 <6 bytes> <cs>
```

Os seis bytes são a ordem dos blocos. Valor original deste aparelho:
`00 01 05 02 03 04`.

### Globais

| Ação | Comando |
|---|---|
| Bypass ON | `00 59 22 09 00 00 04 02 00 00 20 01 00 00 01 D7` |
| Bypass OFF | `... 00 D8` |
| Loopback ON | `00 59 22 09 00 00 04 00 00 00 D0 01 00 00 01 29` |
| Loopback OFF | `... 00 2A` |
| Afinador ON | `00 59 22 09 00 00 04 02 00 10 70 01 00 00 01 77` |
| Afinador OFF | `... 00 78` |
| Consulta afinador | `00 59 23 08 00 00 04 00 00 10 70 06 00 00 75` |
| Consulta de estado global | `00 59 23 08 00 00 04 00 00 00 20 04 00 00 D7` |

### Volume do preset

```
00 59 22 0A 00 00 04 00 00 00 10 02 00 00 <0..100> 00 <cs>
```

## 4. Layout do preset (92 bytes)

| Offset | Campo |
|---|---|
| 0 | volume (0..100) |
| 1 | desconhecido |
| 2..7 | routing (6 bytes) |
| 8 | FX ligado |
| 9 | AMP ligado |
| 10 | MOD ligado |
| 11 | DLY ligado |
| 12 | REV ligado |
| 13 | CAB ligado |
| 14 | modelo FX |
| 15 | modelo AMP |
| 16 | modelo MOD |
| 17 | modelo DLY |
| 18 | modelo REV |
| 19 | modelo CAB |
| 20,22,24,26 | parâmetros FX (uint16 LE) |
| 32,34,36,38,40 | parâmetros AMP |
| 44..54 | parâmetros MOD |
| 56..66 | parâmetros DLY |
| 68..78 | parâmetros REV |
| 80,82,84 | parâmetros CAB |
| 86..91 | desconhecido |

Contagens de modelos observadas: FX 3, AMP 20, MOD 7, DLY 5, REV 6, CAB 20.

## 5. Banco de presets

- 21 slots de 92 bytes, endereço `92 * slot`.
- Arquivo `.tkm` = 92 bytes crus.
- Arquivo `.atkm` = `21 * 92 + b"PATCHEND\x00\x00"` = 1942 bytes.
- Slots 0..20 correspondem aos rótulos `1A..7C`.

## 6. Fluxos compostos

### Save (slot atual)

1. escrever 92 bytes no endereço do slot
2. enviar commit
3. selecionar o slot
4. reler a RAM para confirmar

### Save to (outro slot)

Igual ao save, com o endereço do slot de destino.

### Swap

Não existe comando atômico. O editor lê os dois slots, escreve o conteúdo de A
em B, escreve o conteúdo de B em A, envia um commit e reseleciona.

## 7. AMP e CAB

Ambos usam o **mesmo buffer de modelo**: `area = 0x05`, 8192 bytes, legível e
gravável. O magic no início distingue o conteúdo.

### AMP — `AM2\0`

- Header de 18 bytes: `41 4D 32 00` + 14 bytes zero.
- Payload: estrutura de 6204 bytes (arquivos `.am2Data`).
- O buffer é preenchido até 8192 bytes com zeros.
- Os chunks capturados do editor, concatenados, reproduzem o `.am2Data`
  byte a byte, seguido de padding.

### CAB — `CAB\0`

- Header de 20 bytes: `43 41 42 00` + 14 bytes zero + `01 32` (constante,
  provavelmente versão/largura).
- Payload: **2048 amostras PCM 24-bit little-endian** (6144 bytes).
- Total: 6164 bytes. O restante do buffer fica zerado.

O firmware **normaliza** o IR: a forma de onda é preservada (envelope idêntico
ao WAV de origem), mas a amplitude de cada amostra é ajustada internamente.
Comparando o WAV 48 kHz/24-bit mono de origem com o payload gravado:

| Métrica | Valor |
|---|---|
| Correlação no offset 0 | 0,816 |
| Fator de escala global | 0,851 |
| Envelope RMS por bloco de 128 | idêntico |

Isso significa que **não é possível reproduzir o payload exato** a partir do
WAV sem reimplementar o algoritmo do firmware. Para o app, o caminho prático é:

1. ler o WAV, converter para mono 24-bit;
2. pegar as primeiras 2048 amostras;
3. montar o header e enviar.

O pedal aceita o resultado (o IR toca), mas o ganho pode diferir um pouco do
que o M-EFCS produz. Documentado como aproximação, não como equivalência
bit-a-bit.

### Upload

Blocos de 1015 bytes com offset crescente em `area 0x05`. Capturado do editor
para AMP (7 blocos, 6272 bytes) e para CAB (7 blocos, 6164 bytes).

### Ativação do preview

```
00 59 22 09 00 00 05 00 00 00 A0 01 00 00 <01|02> <cs>
```

`01` para AMP, `02` para CAB. Verificado nas duas capturas.

### Save to Device

Não foi observada nenhuma mensagem MIDI ao clicar em "Save to Device" para CAB
nesta versão do editor — o app falha antes, com
`Null check operator used on a null value` em `import_cab.dart:157`. A causa é
o toast de erro: `errorToast` chama `Overlay.of(context)` sem `context` válido,
e a exceção derruba o aplicativo.

Portanto **a gravação permanente de AMP/CAB no pedal não foi validada**. O que
foi validado é o upload para o buffer em RAM e a ativação por preview. Se a
gravação permanente também for apenas commit do buffer, o comando segue o
mesmo padrão do save de preset; isso é hipótese, não fato.

## 8. Limites conhecidos

- 431 bytes por leitura.
- Taxa: ~3 consultas de estado por segundo.
- Algumas seleções exigem duas leituras até convergir.
- O dispositivo responde `00 59 00 01 00 00 01 FE` para área ou endereço
  inválido.

## 9. O que ainda não foi verificado

- Persistência após desligar o pedal (power-cycle físico).
- Upload de CAB.
- Escrita de AMP com dados diferentes e reboot.
- Factory reset (comando não capturado).
- Comportamento em Linux e Android.
- Áudio real (loopback, bypass, afinador com sinal).

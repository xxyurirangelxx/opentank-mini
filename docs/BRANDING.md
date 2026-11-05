# Identidade visual do OpenTank Mini

A logo já foi criada: um pedal aberto ao meio, com o circuito e a onda de áudio
aparecendo por dentro. Os arquivos ficam em `app/assets/images/` e
`docs/images/`.

| Arquivo | Uso |
|---|---|
| `app/assets/images/logo-symbol.png` | símbolo quadrado, fundo transparente, usado na sidebar |
| `app/assets/images/logo-lockup-dark.png` | símbolo + texto, para fundo escuro |
| `app/assets/images/logo-lockup-light.png` | símbolo + texto, para fundo claro |
| `app/windows/runner/resources/app_icon.ico` | ícone do executável e do instalador |
| `docs/images/logo.png` | logo do README |

O texto "OpenTank" da arte original é quase preto e sumia em fundo escuro; a
versão `-dark` tem esse texto clareado para `#F2F2F3`.

## Prompt usado

```
Crie uma logo para um app open-source chamado "OpenTank Mini", um editor de
presets para pedaleira de guitarra.

Quero algo criativo e marcante, que misture a ideia de pedal de guitarra com
"código aberto" — como se o pedal fosse aberto, mostrando o som por dentro.
Pode brincar com onda de áudio, circuito, chave, botão, formato de pedal.

Estilo: minimalista, geométrico, moderno, fundo transparente, laranja #F59331
como cor principal. Tem que funcionar pequeno (ícone de app) e grande.

Não use nada da marca M-VAVE. É um projeto independente.

Me mostre 3 opções bem diferentes entre si.
```

## Regenerar o ícone a partir de um PNG novo

```python
from PIL import Image

src = Image.open("logo.png").convert("RGBA")
pedal = src.crop((199, 70, 1044, 999))   # ajuste ao recorte do símbolo
pw, ph = pedal.size
side = int(max(pw, ph) * 1.10)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.alpha_composite(pedal, ((side - pw) // 2, (side - ph) // 2))
symbol = canvas.resize((512, 512), Image.LANCZOS)
symbol.save("app/assets/images/logo-symbol.png")
symbol.save(
    "app/windows/runner/resources/app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
```

Depois é só rodar `python tools/build_installer.py`: o instalador pega o ícone
novo automaticamente.

## Regras de marca

A logo **não pode** usar o nome, o logotipo, os símbolos ou a identidade da
M-VAVE. O projeto é não oficial, e uma logo parecida com a do fabricante daria
a entender vínculo que não existe.


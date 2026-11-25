# Spotify Disc — widget para KDE Plasma 6

Mostra a música do Spotify como um disco girando, com visual de MP3 player antigo cinza (tela LCD
verde-acinzentada e direcional redondo), letra sincronizada (LRCLIB), barra de progresso clicável
e controles no direcional: ⏯ no centro, ⏮/⏭ nas laterais, ♥ em cima e letra embaixo.

## Instalar pelo arquivo (sem clonar)
1. Baixe o `spotify-disc-X.Y.plasmoid` na página de [Releases](https://github.com/Lulizza/spotify-disc/releases/latest).
2. Clique com o botão direito na área de trabalho → *Adicionar widgets* → *Obter novos widgets* →
   *Instalar widget de um arquivo local…* e escolha o arquivo baixado.
   Ou, pelo terminal: `kpackagetool6 -t Plasma/Applet -i spotify-disc-X.Y.plasmoid`
   (para atualizar, troque `-i` por `-u`).

Precisa de Plasma 6 e `python3`, este só para o botão Curtir.

## Instalar / atualizar a partir do código
    ./install.sh
Depois: clique com o botão direito na área de trabalho → *Adicionar widgets* → "Spotify Disc".
Para testar em janela: `plasmawindowed local.spotifydisc`.
Após atualizar o código, reinicie o Plasma (`systemctl --user restart plasma-plasmashell`) para recarregar.

## Botão Curtir
O MPRIS não permite curtir músicas, então o botão usa a Spotify Web API:
1. Crie um app em https://developer.spotify.com/dashboard (marque *Web API*).
2. Redirect URI: `http://127.0.0.1:8898/callback`
3. Nas configurações do widget, cole o Client ID e clique em **Conectar ao Spotify**.

O token fica em `~/.config/spotifydisc/token.json` (permissão 600).

## Fonte grafite
Título, artista e tempos usam `package/contents/fonts/SpotifyDiscTag.otf`, gerada a partir de duas
fotos (tinta escura em fundo claro): o alfabeto A–Z em linhas e em ordem, e uma com números e símbolos
nas linhas `12345`, `67890`, `*`, `.,:+-=<>`, `?!(){}[]/"`, `@#€$%&`. Para regerar:

    python3 -m venv venv && venv/bin/pip install pillow numpy scipy scikit-image potracer fonttools
    venv/bin/python tools/build_font.py letras.jpg numeros.jpg package/contents/fonts/SpotifyDiscTag.otf

Minúsculas usam o mesmo desenho das maiúsculas. Os acentos do português (á à â ã é ê í ó ô õ ú ü ç)
são desenhados pelo script, e o apóstrofo é a vírgula levantada. As faixas de linha e a ampliação de
cada linha de símbolos estão em `EXTRA_ROWS`, no script; com outra foto de números, ajuste ali.

## Estrutura
- `package/contents/ui/main.qml` — detecção do Spotify (MPRIS), cores, corpo do MP3 e tela LCD
- `package/contents/ui/DPad.qml` — direcional (tocar, anterior/próxima, curtir, letra)
- `package/contents/ui/Disc.qml` — o disco (máscara em anel, hub, reflexo iridescente)
- `package/contents/ui/LyricsView.qml` — letras via lrclib.net
- `package/contents/code/spotify_like.py` — OAuth PKCE + curtir/descurtir

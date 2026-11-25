#!/bin/sh
# Instala/atualiza o widget e reinicia o plasmashell para recarregar o QML.
set -e
cd "$(dirname "$0")"
if kpackagetool6 -t Plasma/Applet -s local.spotifydisc >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u package
else
    kpackagetool6 -t Plasma/Applet -i package
fi
echo "Instalado. Para testar sem reiniciar o Plasma: plasmawindowed local.spotifydisc"

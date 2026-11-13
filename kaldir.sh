#!/bin/zsh
# Pervane'yi kaldırır; fan sisteme döner.
set -euo pipefail
cd "${0:A:h}"
pkill -x Pervane 2>/dev/null || true
osascript -e "do shell script \"/bin/sh '$PWD/servis.sh' kaldir\" with administrator privileges"
rm -rf "$HOME/Applications/Pervane.app" "$HOME/bin/pervane"
echo "Kaldırıldı. Ayar dosyası duruyor: /Library/Application Support/Pervane/ayar.json"

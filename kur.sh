#!/bin/zsh
# Pervane'yi derler ve kurar: servis (root), menü çubuğu uygulaması, komut satırı aracı.
# Yönetici parolası bir kez sorulur.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Pervane.app"

# Menü çubuğu uygulaması SwiftUI makroları yüzünden tam Xcode ister; yalnız komut satırı araçları
# seçiliyse ve Xcode kuruluysa onu kullan.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == */CommandLineTools && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "Derleniyor…"
swift build -c release 2>&1 | tail -1
BIN=$(swift build -c release --show-bin-path)

# Fansız Mac'te (MacBook Air) sürülecek bir şey yok; servis kurulursa durmadan yeniden başlar.
if ! "$BIN/pervane" sensor 2>/dev/null | grep -q '^Fan '; then
  echo "Bu Mac'te fan bulunamadı (fansız model olabilir); kurulum yapılmadı."
  exit 1
fi

# İki program aynı fana yazarsa birbirini ezer.
if pgrep -xq "Macs Fan Control"; then
  echo "Macs Fan Control kapatılıyor (fan sisteme döner)…"
  osascript -e 'quit app "Macs Fan Control"' || true
  sleep 2
fi

echo "Uygulama paketleniyor: $APP"
pkill -x Pervane 2>/dev/null || true
rm -rf dist && mkdir -p dist/Pervane.app/Contents/MacOS dist/Pervane.app/Contents/Resources
cp "$BIN/PervaneApp" dist/Pervane.app/Contents/MacOS/Pervane
cp Paket/Info.plist dist/Pervane.app/Contents/Info.plist
cp Paket/Pervane.icns dist/Pervane.app/Contents/Resources/Pervane.icns
codesign --force --sign - dist/Pervane.app
mkdir -p "$HOME/Applications" && rm -rf "$APP" && cp -R dist/Pervane.app "$APP"

mkdir -p "$HOME/bin" && cp "$BIN/pervane" "$HOME/bin/pervane"

# Root adımı tek betikte, tek parola sorusuyla.
echo "Servis kuruluyor (yönetici parolası sorulacak)…"
osascript -e "do shell script \"/bin/sh '$PWD/servis.sh' kur '$BIN/pervaned' $(id -u)\" with administrator privileges"

sleep 6
open "$APP"
echo
"$HOME/bin/pervane"

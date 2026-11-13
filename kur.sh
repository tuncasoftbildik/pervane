#!/bin/zsh
# Pervane'yi derler ve kurar: servis (root), menü çubuğu uygulaması, komut satırı aracı.
# Yönetici parolası bir kez sorulur.
set -euo pipefail
cd "${0:A:h}"

LABEL=com.tunca.pervaned
DAEMON=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
APP="$HOME/Applications/Pervane.app"

echo "Derleniyor…"
swift build -c release 2>&1 | tail -1
BIN=$(swift build -c release --show-bin-path)

# İki program aynı fana yazarsa birbirini ezer.
if pgrep -xq "Macs Fan Control"; then
  echo "Macs Fan Control kapatılıyor (fan sisteme döner)…"
  osascript -e 'quit app "Macs Fan Control"' || true
  sleep 2
fi

echo "Uygulama paketleniyor: $APP"
pkill -x Pervane 2>/dev/null || true
rm -rf dist && mkdir -p dist/Pervane.app/Contents/MacOS
cp "$BIN/PervaneApp" dist/Pervane.app/Contents/MacOS/Pervane
cat > dist/Pervane.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.tunca.pervane</string>
  <key>CFBundleName</key><string>Pervane</string>
  <key>CFBundleExecutable</key><string>Pervane</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - dist/Pervane.app
mkdir -p "$HOME/Applications" && rm -rf "$APP" && cp -R dist/Pervane.app "$APP"

mkdir -p "$HOME/bin" && cp "$BIN/pervane" "$HOME/bin/pervane"

# Root adımları tek betikte, tek parola sorusuyla.
ROOT=$(mktemp -t pervane-kur)
cat > "$ROOT" <<ROOTSH
#!/bin/sh
set -e
launchctl bootout system/$LABEL 2>/dev/null || true
install -o root -g wheel -m 755 "$BIN/pervaned" "$DAEMON"
cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DAEMON</string><string>--uid</string><string>$(id -u)</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/pervaned.log</string>
</dict>
</plist>
P
chown root:wheel "$PLIST" && chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"
ROOTSH
echo "Servis kuruluyor (yönetici parolası sorulacak)…"
osascript -e "do shell script \"/bin/sh '$ROOT'\" with administrator privileges"
rm -f "$ROOT"

sleep 6
open "$APP"
echo
"$HOME/bin/pervane"

#!/bin/sh
# Pervane servisini (pervaned) launchd altına kurar ya da kaldırır. Root ister.
#   sudo ./servis.sh kur <pervaned yolu> [kullanıcı kimliği]
#   sudo ./servis.sh kaldir
# Kullanıcı kimliği verilmezse sudo'yu çağıranınki (SUDO_UID) alınır; soket yalnız ona açılır.
set -eu

LABEL=com.tunca.pervaned
DAEMON=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
SOCK=/var/run/pervane.sock

if [ "$(id -u)" -ne 0 ]; then
  echo "root gerekir: sudo $0 $*" >&2
  exit 1
fi

case "${1:-}" in
kur)
  SRC=${2:?"kullanım: sudo $0 kur <pervaned yolu> [kullanıcı kimliği]"}
  OWNER=${3:-${SUDO_UID:-}}
  if [ -z "$OWNER" ] || [ "$OWNER" -eq 0 ]; then
    echo "soketin sahibi olacak kullanıcı bulunamadı; kimliği üçüncü argüman olarak ver" >&2
    exit 1
  fi
  if pgrep -xq "Macs Fan Control"; then
    echo "Uyarı: Macs Fan Control açık. İki program aynı fana yazarsa birbirini ezer; onu kapat." >&2
  fi
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  mkdir -p "$(dirname "$DAEMON")"
  install -o root -g wheel -m 755 "$SRC" "$DAEMON"
  cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$DAEMON</string><string>--uid</string><string>$OWNER</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/pervaned.log</string>
</dict>
</plist>
P
  chown root:wheel "$PLIST"
  chmod 644 "$PLIST"
  launchctl bootstrap system "$PLIST"
  echo "Servis kuruldu: $DAEMON"
  ;;
kaldir)
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$DAEMON" "$SOCK"
  echo "Servis kaldırıldı; fan sisteme döndü."
  ;;
*)
  echo "kullanım: sudo $0 kur <pervaned yolu> [kullanıcı kimliği] | sudo $0 kaldir" >&2
  exit 1
  ;;
esac

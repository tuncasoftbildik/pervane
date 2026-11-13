#!/bin/zsh
# Pervane'yi kaldırır; fan sisteme döner.
set -euo pipefail
LABEL=com.tunca.pervaned
pkill -x Pervane 2>/dev/null || true
osascript -e "do shell script \"launchctl bootout system/$LABEL; rm -f /Library/LaunchDaemons/$LABEL.plist /Library/PrivilegedHelperTools/$LABEL /var/run/pervane.sock\" with administrator privileges"
rm -rf "$HOME/Applications/Pervane.app" "$HOME/bin/pervane"
echo "Kaldırıldı. Ayar dosyası duruyor: /Library/Application Support/Pervane/ayar.json"

#!/usr/bin/env bash
# Install Omarchy-style Firefox start page (local server on :8765)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-firefox-start"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/omarchy-firefox-start.service"
URL_IP="http://127.0.0.1:8765/"
URL_NAME="http://firefox.localhost:8765/"

echo "==> Installing files to $DEST"
mkdir -p "$DEST"
cp -f "$REPO_ROOT/index.html" "$REPO_ROOT/serve.py" "$REPO_ROOT/theme.json" "$DEST/"
cp -f "$REPO_ROOT/omarchy-icon.png" "$DEST/" 2>/dev/null || true
chmod +x "$DEST/serve.py"

echo "==> Writing systemd user service"
mkdir -p "$UNIT_DIR"
cat > "$UNIT" <<'UNIT'
[Unit]
Description=Omarchy Firefox start page (localhost)
After=default.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/omarchy-firefox-start
ExecStart=/usr/bin/python3 %h/.local/share/omarchy-firefox-start/serve.py
Restart=on-failure
RestartSec=1

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now omarchy-firefox-start.service

if ! grep -qE '[[:space:]]firefox\.localhost([[:space:]]|$)' /etc/hosts 2>/dev/null; then
  echo
  echo "Optional: map firefox.localhost -> localhost (needs sudo once):"
  echo "  echo -e '::1 firefox.localhost\\n127.0.0.1 firefox.localhost' | sudo tee -a /etc/hosts"
fi

echo
systemctl --user --no-pager --full status omarchy-firefox-start.service | head -n 12 || true
echo
echo "Open:  $URL_IP"
echo "Or:    $URL_NAME  (after hosts entry)"
echo
echo "Firefox: Settings → Home → set Homepage and New tabs to:"
echo "  $URL_IP"
echo
echo "Customize weather city in: $DEST/index.html  (WEATHER = { ... })"
echo "Done."

#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now omarchy-firefox-start.service 2>/dev/null || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/omarchy-firefox-start.service"
systemctl --user daemon-reload
echo "Service removed. Files left in ~/.local/share/omarchy-firefox-start (delete manually if you want)."

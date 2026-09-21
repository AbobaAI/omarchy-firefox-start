#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now omarchy-firefox-start.service 2>/dev/null || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/omarchy-firefox-start.service"
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/theme-set.d/omarchy-firefox-start"
systemctl --user daemon-reload
echo "Service and theme-set hook removed."
echo "Files left in ~/.local/share/omarchy-firefox-start (delete manually if you want)."
echo "Omafox package (if installed) is left in place — remove with: yay -Rns omafox"

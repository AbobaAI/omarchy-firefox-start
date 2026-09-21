#!/usr/bin/env bash
# Install Omarchy-style Firefox start page (local server on :8765)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-firefox-start"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/omarchy-firefox-start.service"
HOOK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/theme-set.d"
HOOK="$HOOK_DIR/omarchy-firefox-start"
URL_IP="http://127.0.0.1:8765/"
URL_NAME="http://firefox.localhost:8765/"

WITH_OMAFOX=auto
for arg in "$@"; do
  case "$arg" in
    --with-omafox) WITH_OMAFOX=yes ;;
    --without-omafox) WITH_OMAFOX=no ;;
    -h|--help)
      cat <<'HELP'
Usage: ./install.sh [--with-omafox|--without-omafox]

  --with-omafox      install Omafox via yay/paru if missing (Arch/Omarchy)
  --without-omafox  skip Omafox entirely (start page still works with theme.json)
  (default)         detect; offer to install if a TTY is available
HELP
      exit 0
      ;;
  esac
done

omafox_present() {
  command -v omafox >/dev/null 2>&1 && return 0
  [[ -x /usr/bin/omafox ]] && return 0
  pacman -Q omafox >/dev/null 2>&1 && return 0
  return 1
}

install_omafox_pkg() {
  if command -v yay >/dev/null 2>&1; then
    echo "==> Installing omafox with yay"
    yay -S --needed --noconfirm omafox
  elif command -v paru >/dev/null 2>&1; then
    echo "==> Installing omafox with paru"
    paru -S --needed --noconfirm omafox
  else
    echo "!! No yay/paru found. Install Omafox manually, then run: omafox setup"
    return 1
  fi
}

ensure_omafox() {
  if omafox_present; then
    echo "==> Omafox found: $(command -v omafox 2>/dev/null || echo /usr/bin/omafox)"
    return 0
  fi

  echo "==> Omafox not found (optional; live Omarchy theme sync)"
  local do_install=no
  case "$WITH_OMAFOX" in
    yes) do_install=yes ;;
    no)  echo "    Skipping (--without-omafox). Using bundled theme.json."
         return 0 ;;
    auto)
      if [[ -t 0 && -t 1 ]]; then
        read -r -p "    Install Omafox now? [Y/n] " ans || true
        case "${ans:-Y}" in
          n|N|no|NO) do_install=no ;;
          *) do_install=yes ;;
        esac
      else
        echo "    Non-interactive shell: skip. Re-run with --with-omafox to install."
        return 0
      fi
      ;;
  esac

  if [[ "$do_install" == yes ]]; then
    install_omafox_pkg || return 0
  else
    echo "    Continuing without Omafox."
    return 0
  fi

  if omafox_present; then
    echo "==> Running omafox setup + sync"
    omafox setup >/dev/null 2>&1 || omafox setup || true
    omafox sync >/dev/null 2>&1 || true
  fi
}

echo "==> Installing files to $DEST"
mkdir -p "$DEST"
cp -f "$REPO_ROOT/index.html" "$REPO_ROOT/serve.py" "$REPO_ROOT/theme.json" "$DEST/"
cp -f "$REPO_ROOT/omarchy-icon.png" "$DEST/" 2>/dev/null || true
chmod +x "$DEST/serve.py"

ensure_omafox

# Prefer live Omafox palette as the on-disk fallback when available
if [[ -f "${HOME}/.local/state/omafox/theme.json" ]]; then
  cp -f "${HOME}/.local/state/omafox/theme.json" "$DEST/theme.json"
  echo "==> Seeded theme.json from Omafox"
fi

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

echo "==> Installing Omarchy theme-set hook"
mkdir -p "$HOOK_DIR"
cp -f "$REPO_ROOT/hooks/omarchy-firefox-start" "$HOOK"
chmod +x "$HOOK"
# If Omafox package hook is missing but binary exists, add a thin wrapper
if [[ ! -e "$HOOK_DIR/omafox" && -x /usr/bin/omafox ]]; then
  cat > "$HOOK_DIR/omafox" <<'HOOK'
#!/bin/bash
if [[ -x /usr/bin/omafox ]]; then
  exec /usr/bin/omafox sync
fi
exit 0
HOOK
  chmod +x "$HOOK_DIR/omafox"
  echo "    Also wrote $HOOK_DIR/omafox"
fi

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
if omafox_present; then
  echo "Omafox: OK (theme sync on Omarchy theme change via theme-set.d)"
else
  echo "Omafox: not installed — colors come from $DEST/theme.json"
  echo "  Later: ./install.sh --with-omafox   or   yay -S omafox && omafox setup"
fi
echo
echo "Customize weather city in: $DEST/index.html  (WEATHER = { ... })"
echo "Done."

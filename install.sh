#!/usr/bin/env bash
# Install Omarchy-style Firefox start page (local server on :8765)
# + optional Omafox + rectangular (angular) Firefox tabs via userChrome.css
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-firefox-start"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/omarchy-firefox-start.service"
HOOK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/theme-set.d"
HOOK="$HOOK_DIR/omarchy-firefox-start"
TABS_CSS_SRC="$REPO_ROOT/firefox/omarchy-tabs.userChrome.css"
URL_IP="http://127.0.0.1:8765/"
URL_NAME="http://firefox.localhost:8765/"

WITH_OMAFOX=auto
WITH_TABS=yes
for arg in "$@"; do
  case "$arg" in
    --with-omafox) WITH_OMAFOX=yes ;;
    --without-omafox) WITH_OMAFOX=no ;;
    --with-tabs) WITH_TABS=yes ;;
    --without-tabs) WITH_TABS=no ;;
    -h|--help)
      cat <<'HELP'
Usage: ./install.sh [options]

  --with-omafox / --without-omafox   install or skip Omafox (live Omarchy colors)
  --with-tabs / --without-tabs       install rectangular Firefox tabs (default: on)
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

# --- Rectangular Firefox tabs (userChrome.css) ---

firefox_roots() {
  local r
  for r in \
    "${HOME}/.mozilla/firefox" \
    "${HOME}/.config/mozilla/firefox" \
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"
  do
    [[ -d "$r" ]] && printf '%s\n' "$r"
  done
}

firefox_profiles() {
  local root ini path
  while IFS= read -r root; do
    ini="$root/profiles.ini"
    [[ -f "$ini" ]] || continue
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
      else
        printf '%s\n' "$root/$path"
      fi
    done < <(awk -F= '/^Path=/{print $2}' "$ini")
  done < <(firefox_roots)
}

enable_userchrome_pref() {
  local profile=$1 userjs=$1/user.js
  mkdir -p "$profile"
  touch "$userjs"
  if grep -q 'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs" 2>/dev/null; then
    sed -i 's/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets".*);/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);/' "$userjs"
  else
    printf '\nuser_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n' >> "$userjs"
  fi
}

install_tabs_into_profile() {
  local profile=$1
  local chrome="$profile/chrome"
  local uc="$chrome/userChrome.css"
  local block
  [[ -d "$profile" ]] || return 0
  [[ -f "$TABS_CSS_SRC" ]] || { echo "!! Missing $TABS_CSS_SRC"; return 1; }
  block=$(cat "$TABS_CSS_SRC")
  mkdir -p "$chrome"
  if [[ -f "$uc" ]] && grep -q 'BEGIN OMARCHY TABS' "$uc"; then
    # Replace managed block in place
    python3 - "$uc" "$TABS_CSS_SRC" <<'PY'
import pathlib, re, sys
uc = pathlib.Path(sys.argv[1])
block = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
text = uc.read_text(encoding="utf-8")
pat = re.compile(r"/\* BEGIN OMARCHY TABS \*/.*?/\* END OMARCHY TABS \*/\n?", re.S)
if pat.search(text):
    text = pat.sub(block.rstrip() + "\n", text)
else:
    text = text.rstrip() + "\n\n" + block
uc.write_text(text, encoding="utf-8")
PY
  elif [[ -f "$uc" ]]; then
    printf '\n%s\n' "$block" >> "$uc"
  else
    printf '%s\n' "$block" > "$uc"
  fi
  enable_userchrome_pref "$profile"
  echo "    tabs → $uc"
}

install_angular_tabs() {
  if [[ "$WITH_TABS" != yes ]]; then
    echo "==> Skipping rectangular tabs (--without-tabs)"
    return 0
  fi
  if [[ ! -f "$TABS_CSS_SRC" ]]; then
    echo "!! $TABS_CSS_SRC missing — skip tabs"
    return 0
  fi
  echo "==> Installing rectangular Firefox tabs (userChrome.css)"
  local found=0 profile
  while IFS= read -r profile; do
    [[ -d "$profile" ]] || continue
    install_tabs_into_profile "$profile"
    found=1
  done < <(firefox_profiles | sort -u)
  if [[ "$found" -eq 0 ]]; then
    echo "    No Firefox profile found yet. After first Firefox launch, re-run:"
    echo "      $REPO_ROOT/install.sh --without-omafox"
  else
    echo "    Restart Firefox to apply (Enable legacy stylesheets is set in user.js)."
  fi
}

echo "==> Installing files to $DEST"
mkdir -p "$DEST"
cp -f "$REPO_ROOT/index.html" "$REPO_ROOT/serve.py" "$REPO_ROOT/theme.json" "$DEST/"
cp -f "$REPO_ROOT/omarchy-icon.png" "$DEST/" 2>/dev/null || true
chmod +x "$DEST/serve.py"

ensure_omafox

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

install_angular_tabs

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
if [[ "$WITH_TABS" == yes ]]; then
  echo "Tabs: rectangular chrome installed (restart Firefox)"
fi
echo
echo "Customize weather city in: $DEST/index.html  (WEATHER = { ... })"
echo "Done."

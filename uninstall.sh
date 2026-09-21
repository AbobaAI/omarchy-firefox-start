#!/usr/bin/env bash
set -euo pipefail

remove_tabs_block() {
  local uc=$1
  [[ -f "$uc" ]] || return 0
  python3 - "$uc" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
pat = re.compile(r"\n?/\* BEGIN OMARCHY TABS \*/.*?/\* END OMARCHY TABS \*/\n?", re.S)
new, n = pat.subn("\n", text)
if n:
    p.write_text(new.lstrip("\n") if new.startswith("\n\n") else new, encoding="utf-8")
    print(f"    removed tabs block from {p}")
PY
}

echo "==> Stopping start-page service"
systemctl --user disable --now omarchy-firefox-start.service 2>/dev/null || true
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/omarchy-firefox-start.service"
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/hooks/theme-set.d/omarchy-firefox-start"
systemctl --user daemon-reload

echo "==> Removing rectangular tabs CSS block (if present)"
for root in \
  "${HOME}/.mozilla/firefox" \
  "${HOME}/.config/mozilla/firefox" \
  "${HOME}/.var/app/org.mozilla.firefox/.mozilla/firefox"
do
  [[ -f "$root/profiles.ini" ]] || continue
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" == /* ]]; then
      remove_tabs_block "$path/chrome/userChrome.css"
    else
      remove_tabs_block "$root/$path/chrome/userChrome.css"
    fi
  done < <(awk -F= '/^Path=/{print $2}' "$root/profiles.ini")
done

echo "Service and theme-set hook removed."
echo "Files left in ~/.local/share/omarchy-firefox-start (delete manually if you want)."
echo "Omafox package (if installed) is left in place — remove with: yay -Rns omafox"
echo "Restart Firefox if tabs CSS was removed."

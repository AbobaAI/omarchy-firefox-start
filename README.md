# Omarchy Firefox start page

A local Firefox homepage / new-tab page in the Omarchy style: pixel fox, live clock, weather, shortcut tiles, and colors that can follow your system theme.

Runs entirely on your machine (`localhost:8765`). No accounts, no cloud.

## Quick install

```bash
git clone https://github.com/AbobaAI/omarchy-firefox-start.git
cd omarchy-firefox-start
./install.sh
```

Then in Firefox → **Settings → Home**:
- Homepage and new windows → Custom URLs → `http://127.0.0.1:8765/`
- New tabs → same URL

Optional pretty URL:

```bash
echo -e '::1 firefox.localhost\n127.0.0.1 firefox.localhost' | sudo tee -a /etc/hosts
```

Use `http://firefox.localhost:8765/` instead.

## Requirements

- Python 3 (stdlib only)
- `systemd --user` (Linux)
- Firefox (or any browser pointed at the URL)

## Customize

| What | Where |
|------|--------|
| Shortcut tiles | `index.html` — `<a class="tile">…</a>` |
| Weather city | `index.html` — `WEATHER = { latitude, longitude, timezone, label }` |
| Fallback colors | `theme.json` |
| Live Omarchy colors | keep `~/.local/state/omafox/theme.json` updated (Omafox); the server reads it automatically |

Default tiles: YouTube, Gmail, Omarchy, Plugins, Themes, **GitHub**.

## Uninstall

```bash
./uninstall.sh
# optional:
# rm -rf ~/.local/share/omarchy-firefox-start
```

## Manual run (no systemd)

```bash
cd ~/.local/share/omarchy-firefox-start   # or this repo
python3 serve.py
```

## License

MIT

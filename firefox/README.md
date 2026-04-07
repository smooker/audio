# firefox tools — low-level CLI utilities for Firefox

Diagnose and configure Firefox audio/prefs from the command line.
Targets st (smooker) but works on any Linux system with Perl.

## Files

| File | Purpose |
|------|---------|
| `test_alsa.pl` | Inspect running firefox processes: env vars, open `/dev/snd/*`, fuser, /proc/asound/cards |
| `ff_pref.pl` | Edit `~/.mozilla/firefox/<profile>/user.js` from CLI (list/get/set/unset) |
| `test_alsa_firefox.sh` | Wrapper: test current firefox, or kill+start fresh with `ALSA_OUT=<dev>` |

## test_alsa.pl

| Command | Action |
|---------|--------|
| `./test_alsa.pl` | Auto-find firefox PIDs and report |
| `./test_alsa.pl <pid>` | Report only the given PID |
| `./test_alsa.pl <pid1> <pid2>` | Report multiple PIDs |

Output sections:
- ALSA cards (from `/proc/asound/cards`)
- Per PID: cmdline, relevant env (`ALSA_*`, `AUDIODEV`, `APULSE_*`, `PULSE_*`, `MOZ_*`), open audio devices
- `fuser` summary across all `/dev/snd/pcm*p`
- `/proc/asound/pcm` device map
- Interpretation hints (which `Cx` is which card)

## ff_pref.pl

| Command | Action |
|---------|--------|
| `./ff_pref.pl profile` | Print active Firefox profile path |
| `./ff_pref.pl list` | List all prefs in `user.js` |
| `./ff_pref.pl get <key>` | Get pref value |
| `./ff_pref.pl set <key> <value>` | Set pref (auto-detects string/int/bool) |
| `./ff_pref.pl unset <key>` | Remove pref |

Value type auto-detection:
- `42` → int
- `true` / `false` → bool
- anything else → string (auto-quoted)
- `'"already quoted"'` → kept as-is

Backup: writes `user.js.bak` before modifying.

### Common audio prefs

| Pref | Value | Effect |
|------|-------|--------|
| `media.cubeb.backend` | `alsa` | Force ALSA backend (no pulse/sndio/jack) |
| `media.cubeb.alsa.device` | `dmg6` | Direct ALSA device override (if supported) |
| `media.cubeb.log_level` | `verbose` | Cubeb logs to Browser Console (Ctrl+Shift+J) |

### Other useful prefs

| Pref | Value | Effect |
|------|-------|--------|
| `browser.startup.page` | `3` | Restore previous session on startup |
| `privacy.donottrackheader.enabled` | `true` | DNT header |
| `network.cookie.cookieBehavior` | `1` | Block third-party cookies |
| `media.peerconnection.enabled` | `false` | Disable WebRTC (IP leak prevention) |
| `geo.enabled` | `false` | Disable geolocation API |
| `dom.event.clipboardevents.enabled` | `false` | Block clipboard event hijack |

## test_alsa_firefox.sh

| Command | Action |
|---------|--------|
| `./test_alsa_firefox.sh` | Test current firefox (no kill, no start) |
| `./test_alsa_firefox.sh test` | Same as above |
| `./test_alsa_firefox.sh start <dev>` | killall firefox + start with `ALSA_OUT=<dev>` + test |
| `./test_alsa_firefox.sh start dmg6` | Start on G6 USB |
| `./test_alsa_firefox.sh start dmpch` | Start on PCH onboard |
| `./test_alsa_firefox.sh kill` | killall firefox |

## Typical debug session

| Step | Command | Why |
|------|---------|-----|
| 1 | `./test_alsa_firefox.sh test` | See current state |
| 2 | `./ff_pref.pl set media.cubeb.backend alsa` | Force ALSA |
| 3 | `./ff_pref.pl set media.cubeb.log_level verbose` | Enable debug logs |
| 4 | `./test_alsa_firefox.sh start dmg6` | Restart with G6 |
| 5 | `./test_alsa_firefox.sh test` | Verify which `/dev/snd/*` is open |
| 6 | Browser Console (Ctrl+Shift+J) | Read cubeb log to confirm device |

## Notes

- **Firefox MUST be closed** for `prefs.js` writes to stick. `user.js` is read on every startup and overrides `prefs.js`, so it survives Firefox quit cycles.
- `ALSA_OUT` is a custom env var read by our `~/.asoundrc` via `@func getenv` — not a standard ALSA var.
- Firefox content/RDD subprocesses may inherit env from parent — if they don't, audio routing will ignore `ALSA_OUT`. Workaround: `export ALSA_OUT=dmg6` in `~/.bashrc` so it's globally set before firefox starts.
- `media.cubeb.alsa.device` may not exist in older Firefox versions. Check with `ff_pref.pl set` then watch `about:support` → Audio Backend.

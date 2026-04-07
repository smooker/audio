# audio

> **DIGITAL AUDIO STUFF — ALSA ONLY. PulseAudio/PipeWire-FREE ZONE.**

A growing collection of ALSA configurations, helper scripts and diagnostic
tools for running pure-ALSA Linux desktops, with no PulseAudio, no PipeWire,
no JACK in the default audio path.

The driving idea: **one env var (`ALSA_OUT`) selects the output device for
any program**, with `~/.asoundrc` doing the routing via `@func getenv`.

## Why no PulseAudio/PipeWire?

- They are extra moving parts on top of ALSA — for many desktops, just more
  failure modes.
- They make per-program output routing easier *only if* you accept their
  daemon, mixer rules and IPC layer. ALSA `dmix` + `plug` already does
  software mixing and rate conversion.
- They eat resources, occasionally lock devices, and add latency.
- USB DACs, HDMI sinks and Bluetooth (`bluez-alsa`) all have ALSA backends —
  no need for an audio server in the middle.

If your application *requires* PulseAudio API, use [apulse](https://github.com/i-rinat/apulse)
— a tiny shim that translates `libpulse` calls into ALSA. Examples below.

## What's inside

| Path | What |
|------|------|
| `asoundrc` | Reference `~/.asoundrc` with named PCMs and `ALSA_OUT` env-var-driven default |
| `bashrc.alsa` | Bash aliases (`alsa.pch`, `alsa.tv`, `alsa.g6`, `alsa.bt`) |
| `firefox/test_alsa.pl` | Diagnostic — find which `/dev/snd/*` Firefox actually opened |
| `firefox/ff_pref.pl` | CLI editor for Firefox `user.js` (cubeb backend, prefs) |
| `firefox/test_alsa_firefox.sh` | Wrapper: test current firefox or kill+start with `ALSA_OUT` |
| `firefox/README.md` | Per-tool documentation (tables) |
| `howto/ALSA_HOWTO.md` | ALSA setup notes — hardware, dmix, troubleshooting |
| `howto/VIBER_ALSA_HOWTO.md` | Running Viber on pure ALSA via patched apulse |
| `howto/VIBER_HOWTO.md` | Viber on Gentoo (install, Qt5/Qt6, stylesheet) |
| `howto/JACK_HOWTO.md` | JACK for TV audio routing (HDMI playback + snd-dummy capture) |

All Perl scripts have full POD — `perldoc ./ff_pref.pl`.

## The core idea: `ALSA_OUT`

Standard `~/.asoundrc` defines named PCMs:

```
pcm.dmpch  { ... hw:PCH,0    }   # onboard
pcm.dmtv   { ... hw:NVidia,3 }   # HDMI to TV
pcm.dmg6   { ... hw:G6,0     }   # USB DAC
pcm.bluetooth { ... bluealsa }   # BT A2DP
```

…then `pcm.!default` reads an env var to choose between them at runtime:

```
pcm.!default {
    type asym
    playback.pcm {
        @func refer
        name {
            @func concat
            strings [ "pcm." { @func getenv vars [ ALSA_OUT ] default "dmpch" } ]
        }
    }
    capture.pcm { type plug; slave.pcm "hw:PCH,0" }
}
```

Now any program that opens `default` will play through whatever
`ALSA_OUT` says — no per-program config, no daemon.

```
ALSA_OUT=dmg6 mpv hires.flac        # Sound BlasterX G6 (USB)
ALSA_OUT=dmtv vlc movie.mkv         # NVidia HDMI to TV
ALSA_OUT=bluetooth firefox          # BT speaker
ALSA_OUT=dmpch speaker-test -c 2    # onboard
```

`ALSA_OUT` is **not** a standard ALSA env var — it's a local convention,
made real by the `@func getenv` lookup in `.asoundrc`. Could be named
anything. It's chosen because it's short, descriptive and won't clash
with `ALSA_CARD` / `ALSA_PCM_*` semantics.

## Bash aliases (`bashrc.alsa`)

```bash
alias alsa.pch='ALSA_OUT=dmpch'
alias alsa.tv='ALSA_OUT=dmtv'
alias alsa.g6='ALSA_OUT=dmg6'
alias alsa.bt='ALSA_OUT=bluetooth'

# Usage
alsa.g6 mpv file.flac
alsa.tv firefox
```

Source from `~/.bashrc`:

```bash
[ -f ~/path/to/audio/bashrc.alsa ] && . ~/path/to/audio/bashrc.alsa
```

## Firefox: ALSA backend, no pulse

Firefox cubeb library guesses an audio backend (pulse, sndio, jack, alsa).
On a pulse-free machine you'll usually get ALSA, but cubeb may pick the
wrong card if `default` confuses it. Force ALSA explicitly via `user.js`:

```bash
./firefox/ff_pref.pl set media.cubeb.backend alsa
./firefox/ff_pref.pl set media.cubeb.log_level verbose   # Browser Console (Ctrl+Shift+J)
```

Then start firefox with the env var. Subprocesses inherit it (verified
on Gentoo Firefox — sandbox does NOT strip `ALSA_OUT`):

```bash
export ALSA_OUT=dmg6
firefox &
./firefox/test_alsa.pl       # confirms which /dev/snd/pcm*p firefox holds
```

`test_alsa.pl` walks every Firefox process, reads `/proc/PID/environ`
and `/proc/PID/fd`, and prints which audio devices each one holds open
plus a `fuser` summary. The interpretation lines map `Cx` to card names.

## apulse for PulseAudio-only programs

```bash
APULSE_PLAYBACK_DEVICE=dmg6 apulse viber
APULSE_PLAYBACK_DEVICE=dmg6 apulse signal-desktop
```

Use the named PCMs from `.asoundrc` as device names — `apulse` passes
them straight to `snd_pcm_open()`.

## Standard ALSA env vars (for context)

`ALSA_OUT` is custom. The standard libalsa / tool env vars are:

| Var | Used by |
|-----|---------|
| `ALSA_CARD` | libalsa default card hint |
| `ALSA_PCM_CARD` | libalsa default PCM card |
| `ALSA_PCM_DEVICE` | libalsa default PCM device |
| `AUDIODEV` | sox, play, rec |
| `APULSE_PLAYBACK_DEVICE` | [apulse](https://github.com/i-rinat/apulse) |
| `SDL_AUDIODRIVER` / `SDL_AUDIODEV` | SDL apps |

## References

- ALSA project: <https://www.alsa-project.org/>
- ALSA wiki — asoundrc: <https://www.alsa-project.org/wiki/Asoundrc>
- ALSA wiki — Asoundrc parser (`@func`): <https://www.alsa-project.org/alsa-doc/alsa-lib/conf.html>
- `dmix` plugin: <https://www.alsa-project.org/wiki/Asoundrc#The_default_plugin_-_dmix>
- `bluez-alsa`: <https://github.com/arkq/bluez-alsa>
- `apulse`: <https://github.com/i-rinat/apulse>
- Firefox `cubeb` audio library: <https://wiki.mozilla.org/Media/cubeb>
- Mozilla `prefs.js` / `user.js` reference: <https://kb.mozillazine.org/User.js_file>
- Sound BlasterX G6 ALSA support notes: <https://www.alsa-project.org/wiki/Matrix:Module-usb-audio>
- Gentoo USE flag matrix for audio: <https://wiki.gentoo.org/wiki/ALSA>

## Status

Personal config of [smooker (LZ1CCM)](https://github.com/smooker), running
Gentoo on `st`. Tested on a machine with Intel HDA (PCH), NVidia HDMI,
Creative Sound BlasterX G6 USB DAC, and a Bluetooth A2DP speaker.

PRs and issues welcome if you're running pure-ALSA and bumped into
something this repo could solve.

## License

MIT — see [LICENSE](LICENSE).

# Viber on Gentoo with pure ALSA — full HOWTO

Date: 2026-03-30 (latest)
Authors: smooker (LZ1CCM) + claude@st (SCteam)

Running Viber Desktop on Gentoo Linux **without PulseAudio, without
PipeWire, without any sound server** — just ALSA and a patched apulse
shim. Plus the full install, fonts, stylesheet, ICU and DPI workarounds
needed to make Viber actually usable on a sane Linux desktop.

> **Nobody has done this combination before.** No forum posts, no
> guides, no Stack Overflow answers for the pure-ALSA part. This
> document is the entire body of work.

---

## 1. Install

Viber for Linux ships only as `.deb`. Extract the binary tree manually:

```bash
mkdir -p ~/Downloads/viber
cd ~/Downloads/viber
ar x viber.deb
tar xf data.tar.xz
# result: opt/viber/Viber and friends
```

Move the tree to a stable location:

```bash
mkdir -p ~/.local/viber/orig
cp -a opt ~/.local/viber/orig/
# Viber binary lives at ~/.local/viber/orig/opt/viber/Viber
```

### Versions covered

| Host | Viber version | Renderer | Stylesheet handling |
|------|---------------|----------|---------------------|
| `st` | older Viber  | Qt5 widgets | `-stylesheet ~/.viber.css` works directly |
| `sw2`| newer Viber  | Qt6 + Chromium / QtWebEngine | needs env vars (see §4) |

The pure-ALSA work below targets the newer Qt6 build (the older one
doesn't bundle the Qt6Multimedia ffmpeg backend, so it's much easier).

---

## 2. Dependencies — fonts (CRITICAL)

```bash
# Noto — full Unicode glyph coverage as sans fallback
emerge -av media-fonts/noto

# Terminus WITH OTF — bitmap-only Terminus is rejected by Qt6 Chromium!
# package.use:
#   media-fonts/terminus-font otf center-tilde pcf-unicode psf ru-g
emerge -av1 media-fonts/terminus-font
```

> **Without `otf` USE flag on Terminus, the Qt6/Chromium renderer
> refuses to use it.** Only PCF bitmap is not enough — Chromium wants
> an OpenType vector variant.

### Fontconfig profiles

```bash
eselect fontconfig enable 66-noto-sans.conf
eselect fontconfig enable 66-noto-serif.conf
eselect fontconfig enable 66-noto-mono.conf
eselect fontconfig enable 75-noto-emoji-fallback.conf
eselect fontconfig enable 75-yes-terminus.conf
eselect fontconfig enable 70-yes-bitmaps.conf
eselect fontconfig disable 70-no-bitmaps-except-emoji.conf
fc-cache -fv
```

### User fontconfig — Terminus + emoji fallback

```bash
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf << 'EOFCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>Terminus</string></test>
    <edit name="family" mode="append" binding="weak">
      <string>Noto Color Emoji</string>
    </edit>
  </match>
</fontconfig>
EOFCONF
```

---

## 3. Stylesheet

`~/.viber.css`:

```css
* {
    font-family: "Terminus";
    font-size: 12px;
    -webkit-font-smoothing: none;
}
```

**Why these exact values:**

- Use `px`, **not `pt`** — `pt` gets re-scaled through DPI and goes blurry.
- Terminus bitmap sizes are: 12, 14, 16, 18, 20, 22, 24, 28, 32 px.
- `11pt` does NOT exist as a Terminus bitmap → OTF backend scales with
  antialiasing → blur.
- `12px` lands exactly on a bitmap grid → pixel-perfect.
- `-webkit-font-smoothing: none` disables Chromium's antialiasing.

---

## 4. Launcher scripts

### Qt5 (older, no ALSA fixes needed) — `~/bin/viber`

```bash
#!/bin/bash
~/bin/xkb.sh
export QT_QPA_PLATFORMTHEME=gtk3
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR=1
export QTWEBENGINE_CHROMIUM_FLAGS="--force-device-scale-factor=1.0"
LD_LIBRARY_PATH="$HOME/.local/viber/orig/opt/viber/lib" \
  ~/.local/viber/orig/opt/viber/Viber -stylesheet ~/.viber.css "$@"
```

**Why each env var:**

| Var | Reason |
|-----|--------|
| `QT_QPA_PLATFORMTHEME=gtk3` | Without it, Chromium renderer ignores `-stylesheet` |
| `QT_AUTO_SCREEN_SCALE_FACTOR=0` | Disable Qt auto DPR detection |
| `QT_SCALE_FACTOR=1` | Pin Qt scale factor |
| `QTWEBENGINE_CHROMIUM_FLAGS=--force-device-scale-factor=1.0` | Pin Chromium DPR to 1.0; otherwise computed from monitor physical size as e.g. `1.0416…` → blur |
| `LD_LIBRARY_PATH=...viber/lib` | So bundled / symlinked ICU is found |

### Qt6 + pure ALSA — `~/bin/vib`

```bash
#!/bin/bash
pkill -f Viber
VDPAU_DRIVER=none QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" \
  ~/.local/viber/orig/opt/viber/Viber "$@"
```

`VDPAU_DRIVER=none` is mandatory (see §6.3).

---

## 5. Data directory caveat

- `~/.ViberPC/` is shared by Qt5 (older) and Qt6 (newer) Viber builds.
- They are **not** schema-compatible. Switching between Qt5 and Qt6
  builds without wiping `~/.ViberPC/` corrupts the local DB.
- If you change Viber version: `rm -rf ~/.ViberPC/` and log in again.

---

## 6. Pure ALSA stack (the hard part)

Viber Desktop (July 2024 build, bundled Qt 6.5.3) requires PulseAudio for:

- Audio device enumeration (microphone, speakers)
- Audio playback (voice messages, video sound, call audio)
- Video playback AV sync (Qt6Multimedia timestamps depend on the audio clock)

Without it, you get any of:

```
PulseAudioService: failed to subscribe to context notifications
could not load multimedia backend "ffmpeg"
microphone not found
<segfault on video playback>
```

The fix is **three components**, all built from source.

### 6.1 ffmpeg 4.4.6 (custom build, no CUDA)

Viber bundles a Qt6 ffmpeg multimedia plugin (`libffmpegmediaplugin.so`)
that needs ffmpeg 4.x libraries. System ffmpeg 7.x is ABI-incompatible.

```bash
cd ~/work/ffmpeg/ffmpeg-4.4.6
./configure \
  --prefix=$HOME/work/ffmpeg/install \
  --enable-shared \
  --disable-static \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --disable-cuda-llvm \
  --disable-cuvid \
  --disable-nvenc \
  --disable-nvdec \
  --disable-cuda \
  --cc="distcc gcc"
make -j16 CC="distcc gcc"
make install
```

Copy these into `~/.local/viber/orig/opt/viber/lib/`:

- `libavcodec.so.58`
- `libavformat.so.58`
- `libavutil.so.56`
- `libswresample.so.3`
- `libswscale.so.5`

System dependencies:

```bash
emerge -av \
  media-libs/speex \
  media-libs/libopenmpt \
  media-libs/libbluray \
  media-libs/zvbi \
  media-libs/libtheora \
  media-sound/twolame \
  media-sound/wavpack \
  media-libs/xvid
```

> **CRITICAL: build WITHOUT CUDA / CUVID.** With CUDA enabled, Qt6
> selects `h264_cuvid` hardware decoder → NV12 texture format → Qt6
> `textureConverter` is null → segfault on first video frame.

### 6.2 apulse 0.1.14 (patched — 2 fixes)

`apulse` is a tiny shim that translates `libpulse` API calls into ALSA
calls. Stock apulse has two bugs that crash Viber.

#### Patch 1 — `pa_context_subscribe` (apulse-context.c)

Stock `apulse` returns `NULL` from `pa_context_subscribe()`. Viber
treats this as "subscription failed" → audio subsystem doesn't init →
no devices, no AV sync.

```c
// BEFORE (stock apulse):
pa_context_subscribe(...) { return NULL; }

// AFTER (patched):
static void pa_context_subscribe_impl(pa_operation *op) {
    if (op->context_success_cb)
        op->context_success_cb(op->c, 1, op->cb_userdata);
    pa_operation_done(op);
}

pa_context_subscribe(pa_context *c, pa_subscription_mask_t m,
                     pa_context_success_cb_t cb, void *userdata) {
    pa_operation *op = pa_operation_new(c->mainloop_api,
                                        pa_context_subscribe_impl);
    op->c = c;
    op->context_success_cb = cb;
    op->cb_userdata = userdata;
    return op;
}
```

#### Patch 2 — `pa_stream_drain` use-after-free (apulse-stream.c)

Race: `pa_stream_disconnect()` closes the ALSA PCM handle with
`snd_pcm_close(s->ph)`. If `pa_stream_drain` is queued and runs after
disconnect, it calls `snd_pcm_drain()` on a freed handle → SIGSEGV in
libasound.

```c
// In pa_stream_disconnect — null the handle after close:
snd_pcm_close(s->ph);
s->ph = NULL;                       // <-- ADDED
s->state = PA_STREAM_TERMINATED;

// In pa_stream_drain_impl — check before use:
if (op->s && op->s->ph)             // <-- ADDED null check
    snd_pcm_drain(op->s->ph);
```

#### Build

```bash
cd ~/work/alsa/apulse-0.1.14
mkdir build && cd build
cmake .. -DCMAKE_C_COMPILER=gcc -DCMAKE_INSTALL_PREFIX=../install
make -j16 CC="distcc gcc"
```

Copy these into `~/.local/viber/orig/opt/viber/lib/`:

- `libpulse.so.0`
- `libpulse-simple.so.0`
- `libpulse-mainloop-glib.so.0`

### 6.3 VDPAU disable

Qt6 ffmpeg backend auto-selects VDPAU hardware acceleration on NVidia.
VDPAU surfaces (format 100) cannot be converted to textures by Qt 6.5.3
(`textureConverter` is null) → segfault. Force software decode:

```bash
export VDPAU_DRIVER=none
```

This is part of the `vib` launcher above.

---

## 7. Audio pipeline

```
Viber (Qt6Multimedia)
  → libpulse.so.0 (patched apulse, in Viber lib/)
    → libasound.so.2 (system ALSA)
      → dmix (dmpch, ipc_key 192959)
        → hw:PCH,0 (Intel HDA CX11880)
```

Combine with the `ALSA_OUT` switcher from this repo's `asoundrc` and
you can route Viber to any output:

```bash
ALSA_OUT=dmg6 vib   # Viber on the USB Sound BlasterX G6
ALSA_OUT=dmtv vib   # Viber on the HDMI TV
```

---

## 8. What works / what needs testing

| Feature | Status |
|---------|--------|
| Chat (text, images, stickers) | ✅ |
| Audio playback (voice messages) | ✅ |
| Video playback in chat | ✅ |
| Audio output via ALSA (`dmix → hw:PCH,0`) | ✅ |
| Notifications | ✅ |
| Microphone capture | needs testing (after jackd moved to snd-dummy) |
| Voice calls | needs testing |
| Video calls | needs testing |
| Group calls | needs testing |

---

## 9. Common problems

### 9.1 Garbled text — different fonts for digits and letters

**Cause:** missing font with full glyph coverage.
**Fix:** `emerge media-fonts/noto` + the fontconfig profiles in §2.

### 9.2 Terminus is not picked up by stylesheet

**Cause:** Terminus compiled only as PCF bitmap. Qt6/Chromium does not
load bitmap-only fonts.
**Fix:** `USE="otf" emerge terminus-font`.

### 9.3 Terminus is blurry / soft

**Cause:** `font-size` is in `pt` (e.g. `11pt`), which is not a Terminus
bitmap size. The OTF renderer scales + antialiases → blur.
**Fix:** use `font-size: 12px` (or 14px, 16px, … any Terminus bitmap
size) and `-webkit-font-smoothing: none`.

### 9.4 `-stylesheet` does nothing

**Cause:** Qt6 Viber uses the Chromium renderer, not Qt Widgets.
`-stylesheet` only takes effect with `QT_QPA_PLATFORMTHEME=gtk3`.
**Fix:** add the env vars from §4 to the launcher.

### 9.5 DPR ≈ 1.04 → small/blurry text

**Cause:** Xorg computes DPI from EDID physical monitor size. The
result is e.g. `1.0416666666666667`, not a clean integer.
**Fix:** `QTWEBENGINE_CHROMIUM_FLAGS="--force-device-scale-factor=1.0"`.

### 9.6 Vulkan errors at startup

```
vkDebug: setup_loader_term_phys_devs: Failed to detect any valid GPUs
```

**Cause:** Viber Qt6 probes Vulkan. Quadro 4000 (Fermi) has no Vulkan.
**Fix:** harmless — Viber falls back to software rendering.

### 9.7 ICU version mismatch

```
error while loading shared libraries: libicuuc.so.77:
  cannot open shared object file
```

**Cause:** Viber is linked against an older ICU (e.g. 77). After
`emerge @preserved-rebuild` the system has a newer one (e.g. 78). The
Viber binary is prebuilt — not rebuilt.
**Fix:** symlink in Viber's lib dir (NOT in `/usr/lib64`):

```bash
ls /usr/lib64/libicuuc.so.*
ln -s /usr/lib64/libicuuc.so.78  ~/.local/viber/orig/opt/viber/lib/libicuuc.so.77
ln -s /usr/lib64/libicui18n.so.78 ~/.local/viber/orig/opt/viber/lib/libicui18n.so.77
ln -s /usr/lib64/libicudata.so.78 ~/.local/viber/orig/opt/viber/lib/libicudata.so.77
```

The launcher must export `LD_LIBRARY_PATH` to that lib dir.

### 9.8 PulseAudio context error

```
PulseAudioService: pa_context_connect() failed
```

**Cause:** PulseAudio is not installed (intentional).
**Fix:** the §6 stack (patched apulse + ffmpeg 4.4.6 + VDPAU off).
That's the whole point of this document.

---

## 10. Diagnostic commands

```bash
# Fontconfig sees Terminus?
fc-match "Terminus"
fc-match sans

# Which font Viber actually loads:
FC_DEBUG=1 ~/.local/viber/orig/opt/viber/Viber -stylesheet ~/.viber.css \
  2>&1 | grep -E "Terminus|Noto|file:" | head -10

# DPR — look for "qml: DPR: setting dpr X.XX" on stderr.

# All Viber startup errors:
~/.local/viber/orig/opt/viber/Viber 2>&1 | head -30

# Qt6 multimedia debug logging
QT_LOGGING_RULES="qt.multimedia.*=true" vib 2>&1 | tee /tmp/viber_debug.log

# Which libpulse is loaded
LD_DEBUG=libs vib 2>&1 | grep libpulse

# ALSA device access — who holds the playback / capture handle
fuser -v /dev/snd/pcmC0D0p
fuser -v /dev/snd/pcmC0D0c

# Crash analysis with GDB
VDPAU_DRIVER=none QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" \
  gdb -ex run -ex bt --args ~/.local/viber/orig/opt/viber/Viber
```

---

## 11. Key discoveries

1. `--disable-gpu` only affects Chromium / WebEngine, **NOT**
   Qt6Multimedia ffmpeg backend.
2. apulse exports all 60 `pa_*` symbols Viber needs, but
   `pa_context_subscribe` returns NULL — this alone is enough to break
   audio init.
3. Viber `dlopen()`s libpulse at runtime — `LD_PRELOAD` and symlinks
   in `lib/` both work, but RPATH (`$ORIGIN/lib`) takes priority over
   `LD_LIBRARY_PATH`.
4. ffmpeg 4.4.6 built without `--enable-cuda` still picks up system
   CUDA at runtime if NVidia drivers are present — must use
   `VDPAU_DRIVER=none` at runtime.
5. The `pa_stream_drain` segfault is a race in apulse, **not** a
   Viber bug.

---

## 12. System (st reference setup)

- Gentoo Linux, kernel 6.18.2
- NVidia RTX 3000 (driver 590.48.01)
- ALSA only — PulseAudio removed, no PipeWire
- JACK running on separate devices (NVidia HDMI + `snd-dummy`)
- Intel HDA CX11880 for PCH audio (card 0)
- Creative Sound BlasterX G6 USB DAC (card 2)

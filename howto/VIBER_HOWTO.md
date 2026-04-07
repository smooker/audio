# Viber na Gentoo — HOWTO (2026-03-28)

## Versii

- **st:** stara Viber (Qt5 widgets) — `-stylesheet` raboti direktno
- **sw2:** nova Viber (Qt6/Chromium renderer) — triabva env vars za stylesheet

## Instalacia

Viber za Linux se tегли kato .deb ot viber.com, razarhivira se:

```bash
mkdir -p ~/Downloads/viber
cd ~/Downloads/viber
ar x viber.deb
tar xf data.tar.xz
# Rezultat: opt/viber/Viber
```

Na st: kopirano v `~/.local/viber/orig/opt/viber/`

## Dependencii

### Shriftove (KRITICHNO!)

```bash
# Noto — pylen Unicode glyph coverage (sans fallback)
emerge -av media-fonts/noto

# Terminus s OTF (za Qt6/Chromium apps)
# package.use: media-fonts/terminus-font otf center-tilde pcf-unicode psf ru-g
emerge -av1 media-fonts/terminus-font
```

**Bez OTF flag na Terminus — Qt6 Chromium renderer go OTKAZVA!**
Samo PCF bitmap ne se hvashta. OTF e OpenType vector variant.

### Fontconfig profili

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

### User fontconfig — Terminus + Emoji fallback

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

## Stylesheet

`~/.viber.css`:
```css
* {
    font-family: "Terminus";
    font-size: 12px;
    -webkit-font-smoothing: none;
}
```

**VAJNO za font-size:**
- Polzvai `px`, NE `pt`! pt se preizchislqva prez DPI → blur
- Terminus bitmap sizes sa: 12, 14, 16, 18, 20, 22, 24, 28, 32 px
- 11pt NE SYSHTESTVUVA kato bitmap size → OTF go scale-va s antialiasing → blur!
- 12px popada tochno v bitmap grid → piksel-perfekten
- `-webkit-font-smoothing: none` izkluchva Chromium antialiasing

## Launcher script

`~/bin/viber`:
```bash
#!/bin/bash
~/bin/xkb.sh
export QT_QPA_PLATFORMTHEME=gtk3
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR=1
export QTWEBENGINE_CHROMIUM_FLAGS="--force-device-scale-factor=1.0"
LD_LIBRARY_PATH="$HOME/.local/viber/orig/opt/viber/lib" ~/.local/viber/orig/opt/viber/Viber -stylesheet ~/.viber.css "$@"
```

**Kliuchovi env vars:**
- `QT_QPA_PLATFORMTHEME=gtk3` — bez tova Chromium renderer ignorira stylesheet-a
- `QT_AUTO_SCREEN_SCALE_FACTOR=0` — izkluchva auto DPR detection
- `QT_SCALE_FACTOR=1` — fiksira scale factor
- `QTWEBENGINE_CHROMIUM_FLAGS="--force-device-scale-factor=1.0"` — fiksira DPR na 1.0
  (bez tova DPR e 1.0416666666666667 — izchisleno ot fizicheskia razmer na monitora)
- `LD_LIBRARY_PATH` — Viber lib/ direktoriata, za da nameri bundled/symlink-nati ICU libs

## VAJNO — Data directory

- `~/.ViberPC/` — Viber data, login, bazi
- Qt5 (stara) i Qt6 (nova) Viber SPOLDELQT `~/.ViberPC/` — i dvete go polzvat!
- Ako smeniш Viber versiq — `rm -rf ~/.ViberPC/` i login nanovo
- Starata i novata versiq NE sa savmestimi po baza — Qt5 dyni ~/.ViberPC na Qt6 i obratno!

## Problemi i resheniia

### Garbled fonts (razlichni shriftove za cifri i bukvi)

**Prichina:** Lipsvashte shrift s pylen glyph coverage.
**Reshenie:** `emerge media-fonts/noto` + fontconfig profili.

### Terminus ne se hvashta v stylesheet

**Prichina:** Terminus e kompiliran samo kato PCF bitmap. Qt6 Chromium ne poddryzha bitmap fonts.
**Reshenie:** `USE="otf" emerge terminus-font`

### Terminus e blurnat/razmazan

**Prichina:** font-size e v `pt` (napr. 11pt) koeto ne syshtestvuva kato Terminus bitmap size.
OTF renderer-yt scale-va i antialiasva → blur.
**Reshenie:** Polzvai `font-size: 12px` (ili 14px, 16px — samo Terminus bitmap sizes!)
+ `-webkit-font-smoothing: none` v CSS.

### `-stylesheet` ne raboti

**Prichina:** Qt6 Viber polzva Chromium renderer, ne Qt Widgets. `-stylesheet` raboti
samo s `QT_QPA_PLATFORMTHEME=gtk3`.
**Reshenie:** Dobavi env vars v launcher scripta (vizh gore).

### DPR 1.04 (malki/razmazani shriftove)

**Prichina:** Xorg izchislqva DPI ot fizicheskia razmer na monitora (EDID).
**Reshenie:** `QTWEBENGINE_CHROMIUM_FLAGS="--force-device-scale-factor=1.0"`

### Vulkan errors pri start

```
vkDebug: setup_loader_term_phys_devs: Failed to detect any valid GPUs
```

**Prichina:** Viber Qt6 opitva Vulkan. Quadro 4000 (Fermi) niama Vulkan.
**Reshenie:** Bezvredno — Viber fall back na software rendering. Ne prechi.

### ICU version mismatch (libicuuc.so.XX not found)

```
error while loading shared libraries: libicuuc.so.77: cannot open shared object file
```

**Prichina:** Viber e linknat kym stara ICU versiq (napr. 77), a sled `emerge @preserved-rebuild`
sistemata ima po-nova (napr. 78). Viber binary ne se prekompilira — toi e prebuilt.

**Reshenie:** Symlink v Viber lib/ direktoriata (NE v /usr/lib64!):
```bash
# Proveri tekushtata ICU versiq:
ls /usr/lib64/libicuuc.so.*

# Napravi symlinks (primerno 77→78, smeni spored versiqta):
ln -s /usr/lib64/libicuuc.so.78 ~/.local/viber/orig/opt/viber/lib/libicuuc.so.77
ln -s /usr/lib64/libicui18n.so.78 ~/.local/viber/orig/opt/viber/lib/libicui18n.so.77
ln -s /usr/lib64/libicudata.so.78 ~/.local/viber/orig/opt/viber/lib/libicudata.so.77
```

VAJNO: launcher scripta triabva da ima `LD_LIBRARY_PATH` kym Viber lib/ (vizh gore).

### PulseAudio error

```
PulseAudioService: pa_context_connect() failed
```

**Prichina:** PulseAudio ne e instaliran ili ne vyrvi.
**Reshenie:** Ako ne ti triabva zvyk v Viber — ignorirai. Inache `emerge pulseaudio`.

## Diagnostika

```bash
# Kakvo fontconfig podava:
fc-match "Terminus"
fc-match sans

# Koi shrift Viber zarejda realno:
FC_DEBUG=1 ~/.local/viber/orig/opt/viber/Viber -stylesheet ~/.viber.css 2>&1 | grep -E "Terminus|Noto|file:" | head -10

# DPR:
# gledai v stderr: "qml: DPR: setting dpr X.XX"

# Vsichki Viber greshki:
~/.local/viber/orig/opt/viber/Viber 2>&1 | head -30
```

---

# Viber on pure ALSA (no PulseAudio, no pipewire) — SCteam original

Date: 2026-03-30
Authors: smooker + claude@st (SCteam)

## Overview

Running Viber Desktop on Gentoo Linux with pure ALSA — no PulseAudio daemon,
no pipewire, no sound server. Just ALSA and a patched apulse shim.

**Nobody has done this before.** No forum posts, no guides, no Stack Overflow answers.

## The Problem

Viber Desktop (July 2024, bundled Qt 6.5.3) requires PulseAudio for:
- Audio device enumeration (microphone, speakers)
- Audio playback (voice messages, video sound, call audio)
- Video playback AV sync (timestamps depend on audio clock)

Without PulseAudio:
- `PulseAudioService: failed to subscribe to context notifications`
- `could not load multimedia backend "ffmpeg"`
- `microphone not found`
- Video playback → segfault

## The Solution

Three components, all built from source:

### 1. ffmpeg 4.4.6 (custom build, no CUDA)

Viber bundles Qt6 ffmpeg multimedia plugin (`libffmpegmediaplugin.so`) that needs
ffmpeg 4.x libraries. System ffmpeg 7.x is ABI-incompatible.

```bash
cd work/ffmpeg/ffmpeg-4.4.6
./configure \
  --prefix=work/ffmpeg/install \
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

Required libraries (copy to `~/.local/viber/orig/opt/viber/lib/`):
- libavcodec.so.58
- libavformat.so.58
- libavutil.so.56
- libswresample.so.3
- libswscale.so.5

System dependencies (emerge): media-libs/speex, media-libs/libopenmpt,
media-libs/libbluray, media-libs/zvbi, media-libs/libtheora,
media-sound/twolame, media-sound/wavpack, media-libs/xvid

**CRITICAL: Build WITHOUT CUDA/CUVID!** With CUDA enabled, Qt6 selects h264_cuvid
hardware decoder → NV12 texture format → Qt6 textureConverter is null → segfault.

### 2. apulse 0.1.14 (patched — 2 fixes)

apulse is a libpulse shim that routes PulseAudio API calls to ALSA.
Stock apulse has two bugs that crash Viber:

#### Patch 1: pa_context_subscribe (apulse-context.c)

Stock apulse returns NULL from `pa_context_subscribe()`. Viber interprets this
as failure → audio subsystem doesn't initialize → no devices, no AV sync.

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
    pa_operation *op = pa_operation_new(c->mainloop_api, pa_context_subscribe_impl);
    op->c = c;
    op->context_success_cb = cb;
    op->cb_userdata = userdata;
    return op;
}
```

#### Patch 2: pa_stream_drain use-after-free (apulse-stream.c)

Race condition: `pa_stream_disconnect()` closes the ALSA PCM handle with
`snd_pcm_close(s->ph)`. If `pa_stream_drain` is queued and runs after disconnect,
it calls `snd_pcm_drain()` on a freed handle → SIGSEGV in libasound.

```c
// In pa_stream_disconnect — null the handle after close:
snd_pcm_close(s->ph);
s->ph = NULL;  // <-- ADDED
s->state = PA_STREAM_TERMINATED;

// In pa_stream_drain_impl — check before use:
if (op->s && op->s->ph)  // <-- ADDED null check
    snd_pcm_drain(op->s->ph);
```

#### Build

```bash
cd work/alsa/apulse-0.1.14
mkdir build && cd build
cmake .. -DCMAKE_C_COMPILER=gcc -DCMAKE_INSTALL_PREFIX=../install
make -j16 CC="distcc gcc"
```

Copy `libpulse.so.0`, `libpulse-simple.so.0`, `libpulse-mainloop-glib.so.0`
to `~/.local/viber/orig/opt/viber/lib/`.

### 3. VDPAU disable

Qt6 ffmpeg backend auto-selects VDPAU hardware acceleration on NVidia.
VDPAU surfaces (format 100) can't be converted to textures by Qt 6.5.3
(textureConverter is null). Force software decode:

```bash
export VDPAU_DRIVER=none
```

## ALSA launcher script (~/bin/vib)

```bash
#!/bin/bash
pkill -f Viber
VDPAU_DRIVER=none QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" ~/.local/viber/orig/opt/viber/Viber "$@"
```

## What works (ALSA mode)

- Chat (text, images, stickers)
- Audio playback (voice messages)
- Video playback in chat
- Audio output via ALSA (dmix → hw:PCH,0)
- Notifications

## What needs testing

- Microphone input (capture device free after jackd moved to snd-dummy)
- Voice/video calls
- Group calls

## Audio pipeline

```
Viber (Qt6Multimedia)
  → libpulse.so.0 (patched apulse, in Viber lib/)
    → libasound.so.2 (system ALSA)
      → dmix (dmpch, ipc_key 192959)
        → hw:PCH,0 (Intel HDA CX11880)
```

## ALSA debugging commands

```bash
# Qt6 multimedia debug logging
QT_LOGGING_RULES="qt.multimedia.*=true" vib 2>&1 | tee /tmp/viber_debug.log

# Check which libpulse is loaded
LD_DEBUG=libs vib 2>&1 | grep libpulse

# Check ALSA device access
fuser -v /dev/snd/pcmC0D0c  # capture
fuser -v /dev/snd/pcmC0D0p  # playback

# GDB for crash analysis
VDPAU_DRIVER=none QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" \
  gdb -ex run -ex bt --args ~/.local/viber/orig/opt/viber/Viber
```

## Key discoveries

1. `--disable-gpu` only affects Chromium/WebEngine, NOT Qt6Multimedia ffmpeg backend
2. apulse has all 60 pa_* symbols Viber needs, but subscribe returns NULL
3. Viber dlopen()s libpulse at runtime — LD_PRELOAD and symlinks in lib/ both work,
   but RPATH ($ORIGIN/lib) takes priority over LD_LIBRARY_PATH
4. ffmpeg 4.4.6 without --enable-cuda still picks up system CUDA at runtime if
   NVidia drivers are present — must use VDPAU_DRIVER=none at runtime
5. The drain segfault is a race condition in apulse, not a Viber bug

## System (ALSA setup — st)

- Gentoo Linux, kernel 6.18.2
- NVidia RTX 3000 (driver 590.48.01)
- ALSA only (PulseAudio removed, no pipewire)
- JACK running on separate devices (NVidia HDMI + snd-dummy)
- Intel HDA CX11880 for PCH audio (card 0)

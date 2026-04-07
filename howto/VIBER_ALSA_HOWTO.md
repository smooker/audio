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

## Final launcher script (~/bin/vib)

```bash
#!/bin/bash
pkill -f Viber
VDPAU_DRIVER=none QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu" ~/.local/viber/orig/opt/viber/Viber "$@"
```

## What works

- Chat (text, images, stickers) ✅
- Audio playback (voice messages) ✅
- Video playback in chat ✅
- Audio output via ALSA (dmix → hw:PCH,0) ✅
- Notifications ✅

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

## Debugging commands

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

## System

- Gentoo Linux, kernel 6.18.2
- NVidia RTX 3000 (driver 590.48.01)
- ALSA only (PulseAudio removed, no pipewire)
- JACK running on separate devices (NVidia HDMI + snd-dummy)
- Intel HDA CX11880 for PCH audio (card 0)

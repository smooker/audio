# ALSA HOWTO — st.smooker.org

## Хардуер

```
card 0: PCH [HDA Intel PCH], device 0: CX11880 Analog
  - Playback: subdevice #0
  - Capture: subdevice #0

card 1: NVidia [HDA NVidia]
  - HDMI outputs (device 3 = TV)

card 2: (Bluetooth — bluealsa)

card G6: Creative Sound BlasterX G6 (USB DAC, 192kHz)
```

## .asoundrc обзор

### dmix устройства (playback only)

| PCM име | Хардуер | ipc_key | Бележка |
|---------|---------|---------|---------|
| dmpch | hw:PCH,0 | 192959 | Onboard Intel, DEFAULT |
| dmtv | hw:NVidia,3 | 192957 | HDMI към TV |
| dmg6 | hw:G6,0 | 192950 | USB DAC, 192kHz |
| bluetooth | bluealsa | — | BT A2DP (C4:A9:B8:77:F0:1D) |

Default output: `plug → dmpch` (PCH onboard)

### Проблеми

- `dmix` е САМО за playback — `arecord` с dmix дава грешка
- За capture трябва `hw:X,Y` директно, `dsnoop`, или виртуален device

## Capture (микрофон)

### Директен достъп
```bash
arecord -D hw:0,0 -d 3 -f cd /tmp/test.wav
aplay /tmp/test.wav
```

### Кой държи capture device?
```bash
fuser -v /dev/snd/pcmC0D0c
```

### dsnoop (споделен capture, аналог на dmix)
В .asoundrc:
```
pcm.mic {
    type dsnoop
    ipc_key 192960
    slave {
        pcm "hw:PCH,0"
    }
}
```

## JACK

jackd на st държи hw:0,0 (PCH) за TV аудио.
Когато jackd работи — ALSA capture на card 0 е BUSY.

### Проверка
```bash
fuser -v /dev/snd/pcmC0D0c    # capture
fuser -v /dev/snd/pcmC0D0p    # playback
ps aux | grep jackd
```

### Конфликт с Viber
jackd заключва capture device → Viber не може да намери микрофон.
Решения:
1. Отделен USB микрофон (друга карта, jackd не го пипа)
2. snd-aloop (виртуален loopback)
3. snd-dummy (виртуална карта с тишина — за тест/placeholder)
4. Спри jackd преди Viber обаждане

## Виртуални ALSA устройства

### snd-dummy (null device — тишина)
```bash
modprobe snd-dummy
# Създава Dummy карта с playback + capture
# Capture дава тишина — за тест или placeholder
arecord -D hw:Dummy,0 -d 3 -f cd /tmp/silence.wav
```

### snd-aloop (loopback)
```bash
modprobe snd-aloop
# Създава Loopback карта — каквото пуснеш на playback
# излиза на capture (и обратно). Два субустройства.
# Полезно за routing между приложения.
```

### Зареждане при boot (OpenRC)
В `/etc/conf.d/modules`:
```
modules="snd-dummy snd-aloop"
```

## Viber + ALSA (без PulseAudio)

### Статус (2026-03-30)
- PulseAudio НЯМА — махнат, ALSA only
- apulse инсталиран — wrapper за libpulse→ALSA
- apulse НЕ работи с Viber (dlopen, не линква директно)
- Symlink на apulse libpulse в Viber lib/ — не помага (dlopen)
- LD_PRELOAD на apulse — не помага

### ffmpeg multimedia backend — РАБОТИ
Viber bundled Qt6 + ffmpeg plugin търси ffmpeg 4.x:
- libavformat.so.58, libavcodec.so.58, libswresample.so.3, libswscale.so.5, libavutil.so.56
- Системата има ffmpeg 7.x (несъвместимо)
- Решение: компилирахме ffmpeg 4.4.6 локално в `work/ffmpeg/install/`
- Копирани .so файлове в `~/.local/viber/orig/opt/viber/lib/`
- Резултат: `could not load multimedia backend "ffmpeg"` ИЗЧЕЗНА

### PulseAudioService: failed
Остава — Viber ползва PulseAudio за аудио устройства (capture/playback).
ffmpeg backend е за медийни файлове, не за device access.
Без PulseAudio (или pipewire-pulse) — няма микрофон в Viber.

### Опции за микрофон в Viber
1. **pipewire + pipewire-pulse** — лек PulseAudio заместител върху ALSA
2. **pulseaudio** — класически, тежък
3. **USB микрофон** — отделна карта, не конфликтува с jackd
4. **Без микрофон** — Viber работи за чат, няма обаждания

### Viber launcher (~/bin/vib)
```bash
#!/bin/bash
pkill -f Viber
apulse ~/.local/viber/orig/opt/viber/Viber $@
```

### Viber RPATH
```
RUNPATH: $ORIGIN:$ORIGIN/lib
```
Библиотеките се търсят в `opt/viber/` и `opt/viber/lib/`.

## Полезни команди

```bash
# Списък на playback устройства
aplay -l

# Списък на capture устройства
arecord -l

# Тест playback
speaker-test -c 2 -D dmpch

# Тест capture
arecord -D hw:0,0 -d 3 -f cd /tmp/test.wav

# Mixer
alsamixer -c 0

# Кой ползва звуковата карта
fuser -v /dev/snd/*

# ALSA debug
ALSA_DEBUG=1 aplay /tmp/test.wav
```

## bluealsa (Bluetooth A2DP)

```
defaults.bluealsa.service "org.bluealsa"
defaults.bluealsa.device "C4:A9:B8:77:F0:1D"
defaults.bluealsa.profile "a2dp"
defaults.bluealsa.delay 1000
```

Playback only (A2DP е еднопосочен). За BT микрофон трябва HFP профил.

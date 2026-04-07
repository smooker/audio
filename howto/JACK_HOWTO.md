# JACK HOWTO — st.smooker.org

## Използване

JACK на st е за TV аудио routing — playback през HDMI (NVidia), capture от виртуален device (snd-dummy).

## Пускане

```bash
jack.sh 1,3 2
# Аргумент 1: playback device (1,3 = NVidia HDMI device 3 = TV)
# Аргумент 2: capture device (2 = snd-dummy)
```

### Работеща команда (2026-03-30)
```bash
jackd --verbose -dalsa -r48000 -p8192 -n2 -S -Phw:1,3 -Chw:Dummy,0
```

| Флаг | Значение |
|------|----------|
| -dalsa | ALSA драйвер |
| -r48000 | 48kHz sample rate |
| -p8192 | 8192 frames per period (~170ms latency) |
| -n2 | 2 периода (snd-dummy не поддържа 3!) |
| -S | 16-bit (snd-dummy не поддържа 32-bit) |
| -Phw:1,3 | Playback = NVidia HDMI device 3 (TV) |
| -Chw:Dummy,0 | Capture = snd-dummy (виртуален, тишина) |

### Грешки и решения

| Грешка | Причина | Fix |
|--------|---------|-----|
| `cannot configure capture channel` | snd-dummy дава max 2 периода, jackd иска 3 | `-n2` вместо `-n3` |
| `cannot configure capture channel` (32bit) | snd-dummy е 16-bit only | `-S` (force 16-bit) |
| `Cannot lock down memory` | Warning, не fatal | Игнорирай или увеличи `ulimit -l` |
| `Failed to open server` | Общ fail | Виж verbose output за конкретна причина |

## snd-dummy (виртуална карта)

```bash
modprobe snd-dummy
```

- Създава card Dummy с 8 subdevices
- Playback + Capture (capture дава тишина)
- Ползваме го за jackd capture placeholder — така реалният PCH capture остава свободен

### Boot автозареждане (OpenRC)
`/etc/conf.d/modules`:
```
modules="snd-dummy"
```

### Проверка
```bash
arecord -l | grep Dummy
arecord -D hw:Dummy,0 -d 1 -f cd /dev/null  # трябва да работи
```

## Audio routing на st

```
             JACK
              |
    ┌─────────┴─────────┐
    │                    │
 Playback            Capture
 hw:1,3              hw:Dummy,0
 (NVidia HDMI)       (тишина)
    │
    TV

 PCH (hw:0,0) — СВОБОДЕН за ALSA приложения
    ├── Playback: dmix (dmpch) — default output
    └── Capture: директен — за Viber, arecord и т.н.
```

## Полезни команди

```bash
# Статус на JACK
jack_lsp                    # списък на портове
jack_lsp -c                 # с connections
jack_connect port1 port2    # свързване на портове
jack_disconnect port1 port2

# Мониторинг
jack_bufsize                # текущ buffer size
jack_samplerate             # текущ sample rate

# Кой ползва звуковите карти
fuser -v /dev/snd/pcmC0D0c  # PCH capture
fuser -v /dev/snd/pcmC0D0p  # PCH playback
fuser -v /dev/snd/pcmC1D3p  # NVidia HDMI playback

# Kill
pkill jackd
```

## Бележки

- jackd ЗАКЛЮЧВА устройствата които ползва — други приложения не могат да ги отворят
- Затова capture е на snd-dummy, не на PCH — иначе Viber/arecord не могат да ползват микрофона
- HDMI audio (NVidia) може да има различни device номера — провери с `aplay -l`
- G6 (USB DAC) е отделен и не конфликтува

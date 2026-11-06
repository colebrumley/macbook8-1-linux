# Requirements

Every hardware feature of the MacBook8,1, working under Ubuntu 26.10 on the stock kernel plus
the components in this repo. **Verify** names the `scripts/verify.sh` check that decides whether
the item is done. Status values: `done` (check passes), `open`, `blocked` (reason given) and
`manual` (needs a human; the steps are written out).

| ID | What works | Verify | Status |
|---|---|---|---|
| KBD-1 | Internal keyboard: every key and Fn combo, from boot through the LUKS/ZFS prompt | `verify.sh KBD-1` + MAN-1 | done |
| KBD-2 | Keyboard backlight, adjustable from the desktop | `verify.sh KBD-2` | done |
| TP-1 | Trackpad: pointer, click, tap, two-finger scroll, gestures | `verify.sh TP-1` + MAN-1 | done |
| NET-1 | Internal Wi-Fi on 2.4 and 5 GHz, stable across reboot and suspend | `verify.sh NET-1` | done |
| BT-1 | Bluetooth controller up, scans, pairs | `verify.sh BT-1` | done |
| BT-2 | Bluetooth UART at the full 3 Mbaud, so A2DP audio is usable | `verify.sh BT-2` | done |
| BT-3 | Bluetooth patchram firmware loaded (fixes ROM bugs such as the "unknown advertising packet type" spam) | `verify.sh BT-3` | n/a: no BCM4350C0 patch exists; Apple's own Boot Camp stack runs ROM firmware (F-12) |
| AUD-1 | Internal speakers play audio (TDM, 4 ch / 44.1 kHz) and are the desktop default | `verify.sh AUD-1` (`scripts/test-audio.sh`, audible) | done |
| AUD-2 | Internal microphone records | `verify.sh AUD-2` (same loopback) | done |
| AUD-3 | Headphone jack: output, speaker amp muted on insertion, headset mic | MAN-1 | manual: headset mic enabled (F-10); needs headphones/headset to confirm |
| CAM-1 | FaceTime HD camera (Broadcom 1570) captures video | `verify.sh CAM-1` | done |
| GPU-1 | i915 3D acceleration and VA-API video decode | `verify.sh GPU-1` | done |
| DSP-1 | Display brightness control | `verify.sh DSP-1` | done |
| DSP-2 | Ambient light sensor feeds automatic brightness | `verify.sh DSP-2` | done |
| PWR-1 | Battery percentage, charging state, AC detection | `verify.sh PWR-1` | done |
| PWR-2 | Thermal sensors readable; thermald manages the fanless chassis | `verify.sh PWR-2` | done |
| PWR-3 | Suspend to RAM and resume, with keyboard, trackpad, Wi-Fi and Bluetooth still working | `verify.sh PWR-3` | done (deep S3 default; speakers, Wi-Fi, BT, NVMe verified after resume) |
| BT-4 | Bluetooth recovers if its UART setup fails at boot/resume | `verify.sh BT-4` | done |
| PWR-4 | Lid switch triggers suspend | `verify.sh PWR-4` | done |
| STO-1 | NVMe (Apple S1X) healthy, power states working | `verify.sh STO-1` | done |
| USB-1 | USB-C port: charging, USB data, DisplayPort alt-mode output | MAN-1 | manual (port fine; hub latched up once in sleep and recovered on replug, F-8) |

## MAN-1: checks only a person at the machine can do

1. Type every key, including Fn+F1 to F12 (brightness, keyboard light, media, volume).
2. Trackpad: click anywhere on the pad, tap to click, two-finger scroll, three-finger swipe.
3. Speakers play `speaker-test -c2 -t wav -l1`. Plug in headphones: the sound moves to them.
4. Close the lid, wait 10 s, open it. The session resumes and the keyboard works.
5. USB-C: charge from it, use a USB stick and an external display through an adapter.

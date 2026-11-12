# Changelog

## 2026-11-06

- Internal Wi-Fi works (`intel_iommu=off`; brcmfmac DMA was faulting under VT-d).
- Internal keyboard and trackpad work (patched `spi-pxa2xx-pci` forces PIO on MacBook8,1, via DKMS).
- Bluetooth works (DSDT override disables `SSDC` so `BCM2E7C` binds; LPSS DMA blacklisted).
- Repo, verify gate and component installers set up.
- Suspend/resume works: SPI LPSS context restore (spi-pio 1.1) and 8250_lpss PM ops
  (Bluetooth after resume). Five S3 cycles; the last four clean back to back.
- VA-API drivers installed (iHD).
- Audio investigation: loopback tooling (`scripts/audio-route-probe.sh`, `mic-probe.sh`,
  `tone.py`). Speakers/mic still open (F-9).
- Internal speakers and internal mic work (`components/audio`: CS4208 MacBook8,1 fixup;
  the TDM speaker path on 0x0a/0x1d, GPIO0 amp enable, DMIC1). PipeWire sink "MacBook Speakers".
  Proven by acoustic loopback (+67 dB).
- FaceTime HD camera works (`components/camera`: facetimehd + Apple firmware, pinned).
- Headset-jack mic enabled. Bluetooth auto-recovers if its setup fails (`components/bt-recover`).
- Found: no BCM4350C0 Bluetooth patch exists (BT-3 not applicable). The speakers go silent after
  deep S3 because the amp loses its EFI configuration; s2idle avoids it at about 1 W standby (F-14).
- USB-C: the Mac's port is fine; the hub recovered on replug.
- Sleep defaults to s2idle so the speakers survive suspend (`MB81_SLEEP=deep` for long standby).
  PWR-3 now verifies the speakers after resume.
- Speakers survive deep S3: the TDM converter's channel count is restored (found in Apple's EFI
  HDA driver). Deep sleep is the default again.
- NVMe: controller reset after resume (Apple S1X sometimes loses interrupts after deep S3).

## 2026-11-11

- Audio: if the speaker codec is not found at boot ("no codecs found", seen after a forced
  power-off), `mb81-audio-recover` re-probes the HDA controller and restores sound without a
  reboot (F-17, `verify.sh AUD-5`).
- Known issue: one hang on resume after about four days in deep S3, cause unknown; what to
  capture if it happens again is in F-18.

## 2026-11-12

- Audio: `mb81-audio-recover` also re-probes the HDA controller when the codec stops answering
  after a resume (`azx_get_response timeout`, F-17).
- Heat: package power limits (`components/power-limit`, 6 W sustained / 9 W bursts) keep the
  fanless CPU around 76 C under sustained load instead of hard-throttling at 95 C (F-19).
- Power limit is 7 W on the charger, 6 W on battery. `MB81_PSTATE=active` (grub component,
  opt-in) selects the intel_pstate active driver.

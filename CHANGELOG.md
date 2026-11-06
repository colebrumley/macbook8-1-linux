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

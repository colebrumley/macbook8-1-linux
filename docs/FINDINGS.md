# Findings

Root causes found while bringing up a MacBook8,1 (Ubuntu 26.10, kernel 7.3.0-9-generic), newest first.

## F-16: desktop shows "Dummy Output" (speaker sink missing)

- **Cause.** The MacBook Speakers sink is a static `context.objects` adapter, created once at
  PipeWire start. When the user's PipeWire started before the seat session (seen: 10 s
  earlier), opening `hw:PCH,1` failed (`No such device`, no ACL yet), and with `nofail` the
  sink was skipped and never retried.
- **Fix.** Desktop users join the `audio` group (components/audio), so PipeWire can open the
  card whenever it starts.

## F-15: keyboard backlight keys do nothing under COSMIC

- **Cause.** GNOME's settings daemon handles `KEY_KBDILLUM*`. COSMIC's settings daemon stubs
  keyboard brightness (`KeyboardBrightness` always returns -1, and increase/decrease are
  no-ops; upstream `src/main.rs`). The hardware (`spi::kbd_backlight`) is fine.
- **Fix.** `components/kbd-backlight`: a small evdev service steps the level and applies it
  through UPower `KbdBacklight.SetBrightness`. cosmic-osd listens to UPower's
  `BrightnessChanged`, so the native on-screen slider appears. The level persists across
  reboot and resume.
- **Upstream.** Implementing keyboard brightness in cosmic-settings-daemon would make this
  service unnecessary on COSMIC.

## F-14: speakers silent after deep S3 — fixed (converter channel count)

- **Symptom.** Loopback passes at boot and fails after any deep-S3 resume. A driver reload
  doesn't help, and only a reboot does. s2idle doesn't show it.
- **Ruled out.** All coefficients (0x00-0x3f and the test-mode 0x40-0x7f; the 16-bit index
  space mirrors these), GPIO0-5 levels, PCH GPIO51 / `HDEF._PS3`, SMC `AUPO`, any amp on
  SMBus or I2C1, and the amp-enable order.
- **Found in Apple's EFI.** A read-only `flashrom` dump, unpacked with UEFIExtract
  (LongSoft UEFITool), gives the boot-chime HDA driver (DXE `201A92E1-2D0F-48E9-A3AB-93E1695A92F2`,
  strings `layout-id`, `SystemAudioVolume`, `MaximumBootBeepVolume`) and its codec table (raw
  section in `F33528CA-…`). Its init verbs for the CS4208 are exactly the coef image already
  restored. Enumerating every verb opcode the driver builds turned up one Linux never sends to
  this codec: **SET_CVT_CHAN_COUNT (0x72d)**. After deep S3, converter 0x0a reads channel
  count 0. Setting it to 3 (4 channels) brings the speakers back immediately (+72 dB).
- **Why it hid.** A codec reset (driver reload) preserves the register, but a real power loss
  clears it, and generic HDA code only programs it for HDMI.
- **Fix.** `mb81_tdm_prepare()` sets `AC_VERB_SET_CVT_CHAN_COUNT = channels - 1` on 0x0a.
  Verified over repeated deep-S3 cycles via `systemctl suspend`, with loopback after resume.
  Deep sleep is the default again.

## F-13: Bluetooth sometimes misses its first HCI commands at boot

- **Symptom.** `hci0: command 0xfc18 tx timeout`, then `BCM: Reset failed (-110)`. hci0 stays
  DOWN with BD address 00:00:00:00:00:00. Seen on 1 of about 12 boots. The UART and LPSS
  state are healthy, and DMA is still blocked.
- **Fix.** `components/bt-recover`: `mb81-bt-recover.service`, run after boot and from a
  system-sleep hook after resume, waits for hci0 and rebinds `hci_uart_bcm` if needed
  (an ACPI BTPD/BTPU power cycle). A rebind recovered it every time in testing.

## F-12: no BCM4350C0 patchram exists (BT-3 is not applicable)

- The chip reports `BCM4350C0 UART 37.4 MHz Gamay Murata UHE`, ROM 003.001.133 build 1523.
  btbcm has no name for this subversion, so it looks for `brcm/BCM.hcd`.
- Apple's two Boot Camp driver packages for MacBook8,1 (software-update catalog products
  041-88436 sha256 a6b65444…, and 041-98143 sha256 f72f3d43…) ship
  `BroadcomBluetooth64.exe` with 47 .hcd files for BCM4324/4330/4343/4354/4356 and others.
  None is for BCM4350C0, and the BCM4354 files target ROM 003.001.012. Apple's own Windows
  stack therefore runs this chip on ROM firmware, exactly as Linux does now. The community
  BCM4350**C5** files are a different (USB) silicon revision and were deliberately not used.

## F-11: FaceTime HD camera

- **Fix.** `components/camera`: patjak/facetimehd (pinned 4e588ae) via DKMS, plus
  facetimehd-firmware (pinned 961774d). The firmware is extracted from Apple's macOS 10.12.6
  combo update on Apple's CDN, with the Makefile's `curl -k` replaced by `curl --fail`.
  bdc_pci is blacklisted.
- **Verified.** `Apple Facetime HD` appears on /dev/video0 (YUYV, up to 848x588). 30 frames
  captured, luma mean 133 and stdev 46, with frame-to-frame differences: a live image.


## F-10: headset-jack mic (pin 0x18) mic bias sets coef 0x1f bit 10

- **Evidence.** From a clean boot, step by step with `hda-verb`: setting 0x18 pin control to IN
  leaves coef 0x1f = 0x0. Adding VREF80 or VREF50 makes it read 0x400 at once, and dropping VREF
  makes it read 0x0 again. So bit 10 is a **live status**, most likely the mic-bias detector
  (coef 0x34 "A1 Enable, A Thresh = 300 mV") with nothing in the jack. It is not a latched PLL
  fault. Every "PLL fault" seen during F-9 came from a pin map that enabled 0x18.
- **Status.** Speaker loopback with the bias on passes (+66 dB), so 0x18 is enabled in
  `mb81_pincfgs` with auto-mic switching. Capture with a real headset is still a manual check.

## F-9: speakers silent, internal mic dead (CS4208 TDM speaker path) — fixed

- **Symptom.** No sound from the speakers on stock Linux. The internal mic records DC that
  decays to zero (pin 0x1c). Kernel bug 110561.
- **Root causes.**
  1. The speakers are not on the analog DACs. Converter 0x0a feeds pin 0x1d, a 4-slot TDM link
     to the class-D amp. The parser ignores it because the pin's association is 0xf. EFI leaves
     0x0a at format 0x4013 (44.1 kHz / 16-bit / 4 ch) with DigEn 0x111.
  2. **GPIO0 is the amp enable, active high.** EFI parks it low after the chime. Proven by
     loopback: with GPIO0=1 the mic hears the 1 kHz tone at +61 dB; with GPIO0=0, room noise.
  3. The internal mic is DMIC1 on **pin 0x19**. The stock driver matches the PCI SSID
     8086:7270, which it shares with the MacBookAir7,2, and applies `CS4208_MBA6` pin configs.
     Those make 0x1c the mic.
  4. EFI also programs the codec subsystem ID (106b:6400) and the pin defaults. Any codec
     reset brings back chip defaults (SSID 0x10134208), so the fixup is selected by DMI and sets
     every pin explicitly.
- **Fix.** `components/audio` adds a DKMS `snd-hda-codec-cs420x` with a `CS4208_MB81` fixup:
  - The full pin table: HP 0x10, DMIC1 0x19, TDM out 0x1d, everything else N/A.
  - The speaker PCM `hw:PCH,1` is locked to 4 ch / 44.1 kHz / S16.
  - `prepare` replays the EFI coef image, the test-mode ungate (coef 0x40=0x9999, 0x50=0xcb,
    0x40=0), TDM_EN (vendor verb 0x7f0 on NID 0x24) and DigEn 0x111. It then switches the amp
    on with a 75 ms pre-delay. `cleanup` switches it off, and headphone insertion mutes it.
  - The "IEC958 Default PCM" share switch is forced off.

  Also installed: `options snd-hda-intel power_save=0`, and a PipeWire sink "MacBook Speakers"
  (`hw:PCH,1`, FL FR RL RR, stereo up-mix, `nofail`).
- **Verified.** `scripts/test-audio.sh` (audible): 100% of the energy at 1000 Hz, +67.3 dB tone
  ratio. It also passes right after a driver reload, which resets the codec.
- **Rejected.** `probe_only=2 single_cmd=1` (attach without a controller reset) breaks HDMI
  audio and floods the log with spurious responses. The link reset is harmless: codec state
  survives it (`scripts/hda-imm.py` on a boot with snd_hda_intel blocked).
- **Tools.** `hda-imm.py` (talks to the codec without a driver), `cs4208-coef.py`
  (diff/apply the EFI coef image), `tone.py`, `test-audio.sh`, `mb81-audio-live.sh`.

## F-8: USB-C hub lost after one S3 cycle (unconfirmed, needs a replug test)

- **Symptom.** After one of five S3 cycles, the external USB-C hub (Genesys 05e3:0610/0626,
  billboard 291a:8355, plus the TP-Link dongle and a K108D keyboard) disconnected at resume. It
  never re-enumerated, even after an xHCI unbind/bind. AC kept charging through it. That cycle
  also woke 22 s early, which suggests the hub glitched during sleep.
- **Context.** USB-C is managed by an Apple/TI PD controller (`HPM0`, I2C1 addr 0x12, `MODE`
  "APP ", fw 0x00033400, VID 0x0a27, DID 0x18). Nothing binds the Wildcat Point I2C
  controller (8086:9ce2) by default. A live test worked with
  `echo "8086 9ce2 ffffffff ffffffff 0 0 4" > /sys/bus/pci/drivers/i2c-designware-pci/new_id`
  (driver_data 4 = haswell), runtime PM pinned on, and LPSS +0x804=3 / +0x800=1. The firmware
  doesn't recognize the `SSPS` 4CC command (`!CMD`). The other four S3 cycles kept USB.
- **Resolved.** After a physical replug, everything re-enumerated (hub, billboard, keyboard,
  TP-Link). The Mac's port is fine; the adapter latches up when it glitches during sleep.

## F-7: NVMe loses interrupts after some deep-S3 resumes (mitigated)

- **Symptom.** About 3 minutes of `nvme nvme0: I/O tag N QID 1 timeout, completion polled`
  after resume, then hung-task warnings, then recovery.
- **Evidence.** No APST (`npss 0`). MSI is still enabled after resume and the IRQ fires on later
  I/O. Not seen in four later cycles once F-6 was fixed.
- **Seen again** after the F-6 fix, on about 1 in 8 deep resumes: `completion polled`
  timeouts roughly every 60 s, on QID 0 and 1, which share one MSI vector on the Apple S1X.
  PCI config and ASPM are identical before and after resume. A second controller reset
  (`echo 1 > /sys/class/nvme/nvme0/reset_controller`) clears it at once.
- **Mitigation.** `components/nvme-resume`: a systemd-sleep post hook that resets Apple
  106b:2001 controllers after every resume. Zero lost interrupts over the following cycles.
  Root cause still open (probably a ready-timing quirk in the S1X's first post-resume init).
- **Old hypothesis (superseded).** In the first cycle the UART came back held in reset (F-6). It shares
  level-triggered IRQ 21 with SPI, and CPU2 also services the NVMe vector. An interrupt storm
  there could starve NVMe completions. Unconfirmed. `test-suspend.sh` now times a 64 MiB direct
  read after every resume.

## F-6: Bluetooth dead after S3 (UART held in reset)

- **Symptom.** After resume: `hci0: command 0x0c01 tx timeout`, then scans find nothing.
- **Evidence.** `scripts/lpss-regs.py`: UART 00:15.5 +0x804 (LPSS RESETS) is 0x3 at boot and
  0x0 after S3, and +0x820 (TX overflow mask) goes 0x2 → 0x0. `8250_lpss` has no PM ops, so
  nothing suspends or resumes the port.
- **Fix.** `components/uart-lpss` adds suspend/resume to `8250_lpss`. Resume de-asserts the
  resets, re-masks TX overflow, then calls `serial8250_resume_port()`. Four consecutive S3
  cycles passed with a real Bluetooth scan after each.

## F-5: SPI S3 resume (LPSS context)

- **Fix.** `components/spi-pio/patch_resume.py`: save and restore LPSS private registers
  0x00-0x14 around S3, de-asserting the resets first, and ignore the shared IRQ while suspended.
  This mirrors upstream v6 2/2. After resume, LPSS state reads identical to before.

## F-3: Bluetooth UART times out while the LPSS DMA driver is loaded

- **Symptom.** With F-2 fixed, `hci_uart_bcm` binds, then: `hci0: command 0xfc18 tx timeout`,
  `BCM: Reset failed (-110)`. No `hci0` appears.
- **Evidence.** IRQ 20 (`dw:dmac168`, the LPSS DMA controller at 00:15.0) counts 0 for the whole
  boot, while the UART IRQ 21 fires. After unbinding `dw_dmac_pci` and rebinding the serdev
  device, the chip answers at once: `BCM4350C0 UART 37.4 MHz Gamay Murata UHE`, build 1523.
- **Cause.** The same broken LPSS DMA as F-1. `8250_lpss` takes DMA channels whenever
  `dw_dmac_pci` has bound, and those transfers never complete.
- **Fix.** `components/modprobe`: `install dw_dmac_pci /bin/true`. Nothing else on this machine
  uses LPSS DMA.

## F-2: Bluetooth is never created (serdev EBUSY)

- **Symptom.** `serial serial0-0: controller busy`, `failure adding ACPI serdev device. status -EBUSY`.
  No `hci0`.
- **Evidence.** The DSDT has two children under `\_SB.PCI0.URT0`: `SSDC` (`_CID "apple-uart-ssdc"`,
  `_STA` 0x0F) comes first, then `BLTH` (`_HID BCM2E7C`). Serdev allows one device per
  controller, and SSDC takes the slot. SSDC has no Linux driver. Apple's `_DSM` gives it a
  1.25 Mbaud link, which looks like the SMC/sensor UART.
- **Fix.** `components/acpi-dsdt` builds a DSDT override from the firmware's own table with only
  `SSDC._STA` changed to 0 and the OEM revision bumped. dracut adds it as an early cpio
  (`acpi_override`). The kernel log confirms `ACPI: Table Upgrade: override [DSDT-APPLE - MacBook]`.
- **Upstream.** A cleaner fix would be a serdev quirk that skips `apple-uart-ssdc`. Not filed yet.

## F-1: keyboard and trackpad dead ("SPI transfer timed out", -110)

- **Symptom.** `applespi` registers "Apple SPI Keyboard" but every SPI transfer times out, about
  9000 per half hour. The trackpad never appears. Only the ACPI power button works.
- **Evidence.** IRQ 21 (SPI controller 00:15.4) and IRQ 20 (LPSS DMA) both stay at 0. The applespi
  data-ready GPE (`gpe4E`) fires normally.
- **Cause.** On the MacBook8,1, the LPSS DMA handshake between the PXA2xx SSP and the DesignWare
  DMA controller never completes. Known upstream; see the "spi: pxa2xx: disable DMA for Apple
  MacBook8,1" series (v6, July 2026, not merged as of 7.3).
- **Fix.** `components/spi-pio`: DKMS build of `spi-pxa2xx-pci` with a DMI quirk that sets
  `enable_dma = 0` and skips `pm_runtime_allow()`. The patch author found that runtime-suspended
  LPSS plus PIO MMIO access causes a PCIe completion timeout and a watchdog reset. There is also a
  `force_pio=1` module parameter. Result: "Apple SPI Touchpad" registers, `modeswitch done`, IRQ 21
  counts, zero timeouts.
- **Drop when.** The distro kernel carries the upstream quirk (check for `force_pio` in
  `modinfo spi_pxa2xx_pci` from `/lib/modules/*/kernel`).

## F-0: internal Wi-Fi never associates

- **Symptom.** `wlp1s0` sees nothing (`CTRL-EVENT-SCAN-FAILED ret=-12`), and brcmfmac logs
  `Timeout on response for query command` about 35 s after loading.
- **Evidence.** `DMAR: [DMA Read NO_PASID] Request device [0000:01:00.0] ... PTE Read access is not set`.
  The kernel is built with `CONFIG_INTEL_IOMMU_DEFAULT_ON=y`.
- **Cause.** With VT-d on, the BCM4350's DMA to host memory faults. The firmware uses buffers
  that brcmfmac never mapped.
- **Fix.** `components/grub` adds `intel_iommu=off`. After that, scanning and association with
  a 5 GHz WPA2 network work.
- **Note.** brcmfmac warns `no clm_blob available`. No CLM blob for 4350c2 is published, so the
  firmware falls back to its built-in channel table. The 5 GHz networks seen so far all work.

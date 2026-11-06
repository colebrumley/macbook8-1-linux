# macbook8-1-linux

Linux on the **12-inch MacBook (Early 2015, `MacBook8,1`, A1534)** with every piece of hardware
working: internal keyboard and trackpad, Wi-Fi, Bluetooth, speakers and microphone, FaceTime HD
camera, suspend/resume and more. Stock Ubuntu gets almost none of the internals right on this
machine. This repo patches the kernel drivers (via DKMS), overrides one ACPI table, and configures
the rest.

Tested on **Ubuntu 26.10, kernel 7.3**. The installer fetches matching kernel sources for whatever
kernel you run, and refuses to patch if upstream code has changed in a way it doesn't expect.

## Install

Pick one. All three end in the same state.

### 1. Already have Ubuntu installed: one command

```bash
curl -fsSL https://raw.githubusercontent.com/colebrumley/macbook8-1-linux/main/bootstrap.sh | sudo bash
```

This clones the repo to `/opt/macbook8-1-linux`, runs `install.sh`, and reboots. You need a
network connection. Internal Wi-Fi only works *after* this setup, so use a USB Wi-Fi or Ethernet
adapter, or first add `intel_iommu=off` to the kernel command line (see below).

### 2. Bake it into the install media (recommended for a fresh install)

```bash
git clone https://github.com/colebrumley/macbook8-1-linux && cd macbook8-1-linux
tools/make-iso.sh ~/Downloads/ubuntu-26.10-desktop-amd64.iso
# -> ubuntu-26.10-desktop-amd64-macbook8-1.iso
```

Write the new ISO to a USB stick, hold **Option (⌥)** at power-on, and pick *EFI Boot*. The
modified ISO:

- boots the installer with `intel_iommu=off`, so the internal Wi-Fi works during installation;
- runs the normal interactive installer, and at the end arms the hardware setup to run on the
  new system's first boot (`autoinstall/autoinstall.yaml` → `autoinstall/late-commands.sh`).
  The first boot installs everything (about 5-10 minutes, needs network) and reboots once.

> The internal keyboard and trackpad don't work inside the installer: they need the patched
> driver this repo builds. **Use a USB keyboard and mouse to install.** A USB-C hub works.

### 3. Your own autoinstall / provisioning

Add the late command from [`autoinstall/autoinstall.yaml`](autoinstall/autoinstall.yaml) to your
autoinstall config, or run `sudo /opt/macbook8-1-linux/install.sh` from your tooling, then reboot.

### Wi-Fi before setup

Without `intel_iommu=off`, the Broadcom card's DMA faults under the IOMMU and it never connects.
For a one-off boot, press `e` in GRUB and add `intel_iommu=off` to the `linux` line.

## What works

| Hardware | Status | How |
|---|---|---|
| Keyboard, Fn keys, keyboard backlight | ✅ | patched `spi-pxa2xx` (PIO instead of broken LPSS DMA) |
| Trackpad (click, tap, scroll, gestures) | ✅ | same SPI fix (applespi) |
| Wi-Fi (BCM4350) | ✅ | `intel_iommu=off` |
| Bluetooth (BCM4350C0, UART) | ✅ | DSDT override + LPSS DMA off + UART resume fix + auto-recovery |
| Speakers | ✅ | patched CS4208 codec driver: speakers are on a 4-channel TDM link with an amp-enable GPIO |
| Internal microphone | ✅ | same driver (DMIC1) |
| Headphone jack, headset mic | ✅ / ⚠️ | headphones verified; headset mic enabled, not yet tested with a headset |
| FaceTime HD camera | ✅ | `facetimehd` + firmware extracted from Apple's update at install time |
| GPU, VA-API video decode | ✅ | stock i915 + `intel-media-va-driver` |
| Display brightness, ambient light sensor | ✅ | stock (acpi_video, iio-sensor-proxy) |
| Battery, AC, thermals, lid | ✅ | stock |
| Suspend / resume (deep S3) | ✅ | SPI + UART resume patches, NVMe resume reset, speaker channel-count fix |
| USB-C (charging, USB, DisplayPort) | ✅ | stock |
| Bluetooth patch firmware | n/a | none exists for this chip, not even in Apple's Boot Camp drivers |

`sudo /opt/macbook8-1-linux/scripts/verify.sh` checks all of this on your machine.
`sudo /opt/macbook8-1-linux/scripts/manual-check.sh` walks you through the hands-on checks
(keys, trackpad, headphones, external display).

## Sleep

Deep S3 sleep (real, near-zero-power standby) is the default, and everything comes back after
it, speakers included. To use s2idle instead:

```bash
sudo MB81_SLEEP=s2idle /opt/macbook8-1-linux/components/grub/install.sh && sudo reboot
```

## How it works

Each fix is a component in [`components/`](components/), with its root cause and evidence in
[`docs/FINDINGS.md`](docs/FINDINGS.md):

| Component | What it does |
|---|---|
| `spi-pio` | DKMS `spi-pxa2xx`: force PIO on MacBook8,1, LPSS register save/restore across S3 |
| `uart-lpss` | DKMS `8250_lpss`: suspend/resume support (the UART stays in reset after S3) |
| `modprobe` | blocks `dw_dmac_pci` (LPSS DMA never completes on this machine) |
| `acpi-dsdt` | DSDT override built from *your* firmware's table: frees the UART for Bluetooth |
| `audio` | DKMS `snd-hda-codec-cs420x` with a MacBook8,1 fixup, plus a PipeWire speaker sink |
| `camera` | `facetimehd` driver and firmware |
| `bt-recover` | rebinds Bluetooth if its UART setup misses at boot/resume |
| `nvme-resume` | resets the Apple NVMe after resume (it sometimes loses interrupts otherwise) |
| `grub` | `intel_iommu=off`, sleep mode |
| `firstboot` | used by the install-media path: runs the installer once on first boot |

Kernel patches are generated from vanilla upstream sources by the `patch_*.py` scripts, keyed
by your kernel version, and rebuilt automatically by DKMS on kernel updates.

## Uninstalling

```bash
sudo dkms remove spi-pxa2xx-pio --all; sudo dkms remove 8250-lpss-pm --all
sudo dkms remove cs4208-mb81 --all;    sudo dkms remove facetimehd --all
sudo rm /usr/lib/firmware/acpi/dsdt.aml /etc/dracut.conf.d/90-acpi-override.conf \
        /etc/modprobe.d/macbook81-no-lpss-dma.conf /etc/modprobe.d/mb81-*.conf
sudo systemctl disable mb81-bt-recover.service
sudo cp /etc/default/grub.macbook8-1-linux.orig /etc/default/grub && sudo update-grub
sudo update-initramfs -u -k all && sudo reboot
```

## Contributing

See [AGENTS.md](AGENTS.md). Fixes go in components, every claim needs a `verify.sh` check, and
root causes go in FINDINGS. Kernel patches are written to be upstreamable.

## License

GPL-2.0 (see [LICENSE](LICENSE)). The vendored kernel sources under `components/*/upstream/`
are from Linux and carry their own GPL-2.0 headers. No Apple firmware is included: the camera
firmware is downloaded from Apple and extracted on your machine at install time.

# AGENTS.md: how work gets done here

`macbook8-1-linux` makes every piece of hardware in the 12-inch MacBook (Early 2015,
`MacBook8,1`, Broadwell-Y) work under Ubuntu. The backlog is [REQUIREMENTS.md](REQUIREMENTS.md):
each item says what must work and carries a **Verify** line that decides whether it is done.
A machine's whole state must be reproducible from this repo with `sudo ./install.sh`.

These rules apply to people and to coding agents alike.

## Rules

1. **Every change to the system lives in this repo.** Don't hand-edit `/etc`, `/boot` or
   `/usr/lib/firmware` without a component that does the same thing and survives a reinstall.
   Each component sits in `components/<name>/` with an idempotent `install.sh`; the top-level
   `install.sh` runs them in order.
2. **Verify before you claim.** `scripts/verify.sh` is the gate. A requirement is `done` only
   after its check passes on a real MacBook8,1. Checks that need a human (looking, listening,
   plugging things in) are `MANUAL`, recorded by `scripts/manual-check.sh`, and never count as
   automated passes.
3. **Be careful with boot-affecting changes.** Kernel command line, DSDT override, initramfs
   and bootloader changes can leave a machine unbootable. Test one per reboot, and keep a way
   back: `scripts/snapshot.sh <label>` takes a ZFS snapshot if root is on ZFS. `/boot` is
   usually not covered, so keep the previous initramfs recoverable.
4. **Never cut off your access path.** When working over SSH, keep a second network path (a
   USB Wi-Fi or Ethernet adapter) until internal Wi-Fi has survived reboots and suspend.
5. **Write down why.** Every non-obvious fix gets a [docs/FINDINGS.md](docs/FINDINGS.md) entry:
   symptom, evidence (log lines, register values), root cause, fix, upstream status. Record
   user-visible changes in [CHANGELOG.md](CHANGELOG.md).
6. **Prefer upstreamable fixes.** Kernel changes are clean patches gated by a DMI quirk, built
   with DKMS so kernel updates rebuild them. Track upstream status in FINDINGS, and drop a
   local patch once the distro kernel carries the fix.
7. **Never ship machine data or vendor blobs.** No firmware dumps, DSDT copies, serial
   numbers, MAC addresses, hostnames or network names in commits. Firmware is fetched or
   extracted on the user's machine at install time.
8. **Small commits, clear messages.** One requirement or fix per commit.

## Sound tests are audible

`scripts/test-audio.sh`, `audio-route-probe.sh`, `mic-probe.sh`, `mb81-audio-live.sh`,
`mb81-amp-*.sh` and `test-suspend.sh` with `AUDIO=1` play tones on the speakers. Someone may be
sitting next to the machine. Only run them with the owner's OK, keep levels low, and never loop.

## Layout

```
bootstrap.sh            curl | sudo bash entry point: clone to /opt, install, reboot
install.sh              run every component installer (idempotent)
autoinstall/            Ubuntu installer hook (autoinstall.yaml + late-commands.sh)
tools/make-iso.sh       remaster an Ubuntu ISO into a MacBook8,1 installer
components/<name>/      one fix each: install.sh + sources/patch generator
scripts/verify.sh       hardware acceptance checks, PASS/FAIL/MANUAL per requirement
scripts/manual-check.sh guided hands-on checks
docs/FINDINGS.md        root causes and evidence
```

## Session start

```bash
cd /opt/macbook8-1-linux && git pull --ff-only; git log --oneline -5
sudo ./scripts/verify.sh        # what works right now
```

Pick the highest-priority item in REQUIREMENTS.md that isn't `done`, fix it in a component,
run `verify.sh`, update REQUIREMENTS / FINDINGS / CHANGELOG, and commit.

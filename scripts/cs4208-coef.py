#!/usr/bin/env python3
"""Read / diff / restore CS4208 vendor coefficients through the ALSA hwdep (driver loaded).

  sudo cs4208-coef.py dump                 print coefs 0x00-0x7f
  sudo cs4208-coef.py diff  <efi.json>     live vs captured EFI image (components/audio/efi-codec-state.json)
  sudo cs4208-coef.py apply <efi.json> [--only 0x00,0x03,...]   write EFI values that differ
Skips 0x1f (PLL status, read-only).
"""
import fcntl
import glob
import json
import os
import struct
import sys

HDA_IOCTL_VERB_WRITE = 0xC0084811  # _IOWR('H', 0x11, struct hda_verb_ioctl)
VENDOR_NID = 0x24
STATUS_ONLY = {0x1f}


def find_hwdep():
    for p in glob.glob("/sys/class/sound/hwC*D*/vendor_id"):
        if open(p).read().strip() == "0x10134208":
            return "/dev/snd/" + p.split("/")[-2]
    sys.exit("no CS4208 hwdep found")


class Codec:
    def __init__(self):
        self.fd = os.open(find_hwdep(), os.O_RDWR)

    def verb(self, nid, verb, param):
        vid = verb >> 8 if verb > 0xf else verb
        if vid in (0x2, 0x3, 0x4, 0x5, 0xa, 0xb, 0xc, 0xd):
            v = (nid << 24) | (vid << 16) | (param & 0xffff)
        else:
            v = (nid << 24) | (verb << 8) | (param & 0xff)
        buf = bytearray(struct.pack("<II", v, 0))
        fcntl.ioctl(self.fd, HDA_IOCTL_VERB_WRITE, buf)
        return struct.unpack("<II", buf)[1]

    def get(self, idx):
        self.verb(VENDOR_NID, 0x5, idx)
        return self.verb(VENDOR_NID, 0xc00, 0)

    def set(self, idx, val):
        self.verb(VENDOR_NID, 0x5, idx)
        self.verb(VENDOR_NID, 0x4, val)


def main():
    c = Codec()
    cmd = sys.argv[1]
    if cmd == "dump":
        for i in range(0x80):
            print(f"{i:#04x} {c.get(i):#06x}")
        return
    efi = {int(k, 16): int(v, 16) for k, v in json.load(open(sys.argv[2]))["coef"].items()}
    only = None
    if "--only" in sys.argv:
        only = {int(x, 16) for x in sys.argv[sys.argv.index("--only") + 1].split(",")}
    for i in range(0x80):
        if i in STATUS_ONLY or (only is not None and i not in only):
            continue
        live = c.get(i)
        if live != efi.get(i, 0):
            if cmd == "diff":
                print(f"{i:#04x} live={live:#06x} efi={efi.get(i, 0):#06x}")
            elif cmd == "apply":
                c.set(i, efi.get(i, 0))
                after = c.get(i)
                print(f"{i:#04x} {live:#06x} -> {after:#06x}{'' if after == efi.get(i, 0) else '  (did not stick)'}")


if __name__ == "__main__":
    main()

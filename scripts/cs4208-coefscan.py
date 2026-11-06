#!/usr/bin/env python3
"""Scan the full 16-bit CS4208 vendor coefficient index space (NID 0x24), in the normal
view and in test mode (coef 0x40 = 0x9999), and print every non-zero value.
Read-only apart from toggling test mode (restored at the end). Driver must be loaded.

  sudo cs4208-coefscan.py > scan.txt        (compare two scans with diff)
"""
import fcntl
import glob
import os
import struct
import sys

IOCTL = 0xC0084811  # HDA_IOCTL_VERB_WRITE
NID = 0x24


def hwdep():
    for p in glob.glob("/sys/class/sound/hwC*D*/vendor_id"):
        if open(p).read().strip() == "0x10134208":
            return "/dev/snd/" + p.split("/")[-2]
    sys.exit("no CS4208")


fd = os.open(hwdep(), os.O_RDWR)


def verb(v4, payload):
    buf = bytearray(struct.pack("<II", (NID << 24) | (v4 << 16) | (payload & 0xFFFF), 0))
    fcntl.ioctl(fd, IOCTL, buf)
    return struct.unpack("<II", buf)[1]


def get(i):
    verb(0x5, i)
    return verb(0xC, 0)


def setc(i, v):
    verb(0x5, i)
    verb(0x4, v)


for mode in ("n", "t"):
    if mode == "t":
        setc(0x40, 0x9999)
    for i in range(0x10000):
        if mode == "t" and i == 0x40:
            continue
        v = get(i)
        if v not in (0, 0xFFFFFFFF):
            print(f"{mode} {i:04x} {v:#06x}")
    if mode == "t":
        setc(0x40, 0x0000)

#!/usr/bin/env python3
"""Dump LPSS private registers (BAR0 + 0x800..0x84c) for the LPSS PCI functions.

Read-only. Useful to compare state before and after S3:
  sudo scripts/lpss-regs.py            # SPI 00:15.4 and UART 00:15.5
  sudo scripts/lpss-regs.py 0000:00:15.5
"""
import mmap
import os
import struct
import sys

DEVS = sys.argv[1:] or ["0000:00:15.4", "0000:00:15.5"]
NAMES = {0x800: "clk/params", 0x804: "resets", 0x808: "general", 0x80c: "ssp/sw_ltr",
         0x810: "auto_ltr", 0x818: "cs_ctrl", 0x820: "tx_ovf_int", 0x838: "clock_gate"}

for dev in DEVS:
    path = f"/sys/bus/pci/devices/{dev}/resource0"
    fd = os.open(path, os.O_RDONLY | os.O_SYNC)
    try:
        m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ)
        print(f"{dev}:")
        for off in range(0x800, 0x850, 4):
            (v,) = struct.unpack("<I", m[off:off + 4])
            print(f"  +0x{off:03x} {NAMES.get(off, ''):<11} 0x{v:08x}")
        m.close()
    finally:
        os.close(fd)

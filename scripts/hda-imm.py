#!/usr/bin/env python3
"""Talk to an HDA codec through the controller's Immediate Command interface (MMIO).

Use ONLY when no driver is bound to the controller (snd_hda_intel blocked), e.g. to dump
the codec state that EFI left behind, without the link reset a driver would do.

  sudo hda-imm.py [--dev 0000:00:1b.0] [--cad 0] status
  sudo hda-imm.py verb <nid> <verb> <param>        e.g. verb 0x01 0xf00 0x00
  sudo hda-imm.py coef <idx> [<value>]             vendor coef on NID 0x24 (read / write)
  sudo hda-imm.py dump                             JSON: coefs 0x00-0x7f, GPIO, pins, converters
  sudo hda-imm.py linkreset                        toggle GCTL.CRST (what a driver does at probe)

Verb encoding: 12-bit verbs (0x700..0xfff) take an 8-bit param; 4-bit verbs
(0x2xx/0x3xx/0x4xx/0x5xx, 0xaxx/0xbxx) take a 16-bit payload: pass e.g. `verb 0x24 0x5 0x1f`.
"""
import argparse
import json
import mmap
import os
import struct
import sys
import time

GCTL, STATESTS, CORBCTL, RIRBCTL, IC, IR, ICS = 0x08, 0x0e, 0x4c, 0x5c, 0x60, 0x64, 0x68
ICB, IRV = 0x1, 0x2
VENDOR_NID = 0x24


class Hda:
    def __init__(self, dev, cad):
        drv = f"/sys/bus/pci/devices/{dev}/driver"
        if os.path.exists(drv):
            sys.exit(f"{dev} is bound to {os.path.basename(os.readlink(drv))}; refusing (unbind/block it first)")
        cfg = f"/sys/bus/pci/devices/{dev}/config"
        with open(cfg, "r+b") as f:  # make sure memory decoding is on
            f.seek(4)
            cmd = struct.unpack("<H", f.read(2))[0]
            if not cmd & 0x2:
                f.seek(4)
                f.write(struct.pack("<H", cmd | 0x6))
        self.fd = os.open(f"/sys/bus/pci/devices/{dev}/resource0", os.O_RDWR | os.O_SYNC)
        self.m = mmap.mmap(self.fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        self.cad = cad

    def r32(self, o): return struct.unpack("<I", self.m[o:o + 4])[0]
    def r16(self, o): return struct.unpack("<H", self.m[o:o + 2])[0]
    def r8(self, o): return self.m[o]
    def w32(self, o, v): self.m[o:o + 4] = struct.pack("<I", v)
    def w16(self, o, v): self.m[o:o + 2] = struct.pack("<H", v)
    def w8(self, o, v): self.m[o:o + 1] = bytes([v])

    def status(self):
        return {"GCTL": hex(self.r32(GCTL)), "STATESTS": hex(self.r16(STATESTS)),
                "CORBCTL": hex(self.r8(CORBCTL)), "RIRBCTL": hex(self.r8(RIRBCTL)), "ICS": hex(self.r16(ICS))}

    def ensure_imm(self):
        # immediate commands and CORB/RIRB DMA are mutually exclusive: stop the DMA engines
        for reg in (CORBCTL, RIRBCTL):
            v = self.r8(reg)
            if v & 0x2:
                self.w8(reg, v & ~0x2)
                time.sleep(0.01)

    def send(self, nid, verb, param=0):
        # 4-bit verb ids (16-bit payload): 0x2 fmt, 0x3 amp set, 0x4 coef, 0x5 coef idx,
        # 0xa fmt get, 0xb amp get, 0xc coef get, 0xd coef idx get. Accept 0x5 or 0x500 style.
        vid = verb >> 8 if verb > 0xf else verb
        if vid in (0x2, 0x3, 0x4, 0x5, 0xa, 0xb, 0xc, 0xd):
            cmd = (self.cad << 28) | (nid << 20) | (vid << 16) | (param & 0xffff)
        else:
            cmd = (self.cad << 28) | (nid << 20) | (verb << 8) | (param & 0xff)
        for _ in range(1000):
            if not self.r16(ICS) & ICB:
                break
            time.sleep(0.0001)
        else:
            raise TimeoutError("ICB stuck busy")
        self.w32(IC, cmd)
        self.w16(ICS, IRV | ICB)  # clear IRV (W1C), start
        for _ in range(10000):
            s = self.r16(ICS)
            if not s & ICB and s & IRV:
                return self.r32(IR)
            time.sleep(0.0001)
        raise TimeoutError(f"no response for cmd {cmd:#010x}")

    def coef(self, idx, value=None):
        self.send(VENDOR_NID, 0x5, idx)
        if value is not None:
            self.send(VENDOR_NID, 0x4, value)
            self.send(VENDOR_NID, 0x5, idx)
        return self.send(VENDOR_NID, 0xc00, 0)

    def dump(self):
        d = {"controller": self.status()}
        d["vendor_id"] = hex(self.send(0x00, 0xf00, 0x00))
        d["subsystem_id"] = hex(self.send(0x01, 0xf20, 0x00))
        d["afg_power"] = hex(self.send(0x01, 0xf05, 0x00))
        d["gpio"] = {k: hex(self.send(0x01, v, 0)) for k, v in
                     (("data", 0xf15), ("mask", 0xf16), ("dir", 0xf17), ("wake", 0xf18), ("unsol", 0xf19), ("sticky", 0xf1a))}
        d["coef"] = {f"{i:#04x}": hex(self.coef(i)) for i in range(0x00, 0x80)}
        nodes = {}
        for nid in range(0x02, 0x25):
            n = {"power": hex(self.send(nid, 0xf05, 0)),
                 "conv": hex(self.send(nid, 0xa00, 0)) if nid <= 0x0f else None,
                 "stream": hex(self.send(nid, 0xf06, 0)) if nid <= 0x0f else None,
                 "digi": hex(self.send(nid, 0xf0d, 0)) if 0x0a <= nid <= 0x0f else None,
                 "pinctl": hex(self.send(nid, 0xf07, 0)) if 0x10 <= nid <= 0x22 else None,
                 "eapd": hex(self.send(nid, 0xf0c, 0)) if 0x10 <= nid <= 0x22 else None,
                 "conn_sel": hex(self.send(nid, 0xf01, 0)),
                 "amp_out_l": hex(self.send(nid, 0xb00, 0xa000)), "amp_out_r": hex(self.send(nid, 0xb00, 0x8000)),
                 "amp_in_l": hex(self.send(nid, 0xb00, 0x2000)), "amp_in_r": hex(self.send(nid, 0xb00, 0x0000))}
            nodes[f"{nid:#04x}"] = {k: v for k, v in n.items() if v is not None}
        d["nodes"] = nodes
        return d

    def linkreset(self):
        g = self.r32(GCTL)
        self.w32(GCTL, g & ~1)
        for _ in range(1000):
            if not self.r32(GCTL) & 1:
                break
            time.sleep(0.0001)
        time.sleep(0.001)
        self.w32(GCTL, self.r32(GCTL) | 1)
        for _ in range(1000):
            if self.r32(GCTL) & 1:
                break
            time.sleep(0.0001)
        time.sleep(0.01)
        return self.status()


def num(s): return int(s, 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dev", default="0000:00:1b.0")
    ap.add_argument("--cad", type=int, default=0)
    ap.add_argument("cmd")
    ap.add_argument("args", nargs="*", type=num)
    a = ap.parse_args()
    h = Hda(a.dev, a.cad)
    if a.cmd == "status":
        print(json.dumps(h.status()))
        return
    if a.cmd == "linkreset":
        print(json.dumps(h.linkreset()))
        return
    h.ensure_imm()
    if a.cmd == "verb":
        print(hex(h.send(*a.args)))
    elif a.cmd == "coef":
        print(hex(h.coef(*a.args)))
    elif a.cmd == "dump":
        print(json.dumps(h.dump(), indent=1))
    else:
        sys.exit(f"unknown command {a.cmd}")


if __name__ == "__main__":
    main()

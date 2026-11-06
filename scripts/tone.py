#!/usr/bin/env python3
"""Tiny audio helper for the loopback tests.

  tone.py <freq> <seconds> [rate] [channels]   raw S16_LE sine on stdout (default 48 kHz stereo)
  tone.py analyze <file.wav>    print DC, RMS and the 1 kHz tone ratio (Goertzel, dB)
"""
import math
import struct
import sys
import wave

RATE = 48000


def tone(freq, secs, amp=2500, rate=RATE, ch=2):  # ~-22 dBFS: audible, not startling
    n = int(rate * secs)
    out = bytearray()
    fmt = "<" + "h" * ch
    for i in range(n):
        v = int(amp * math.sin(2 * math.pi * freq * i / rate))
        out += struct.pack(fmt, *([v] * ch))
    sys.stdout.buffer.write(out)


def goertzel(x, f, rate=RATE):
    k = 2 * math.cos(2 * math.pi * f / rate)
    a = b = 0.0
    for v in x:
        a, b = v + k * a - b, a
    return a * a + b * b - k * a * b


def analyze(path, f0=1000):
    w = wave.open(path)
    d = w.readframes(w.getnframes())
    s = struct.unpack("<%dh" % (len(d) // 2), d)[0::w.getnchannels()]
    mean = sum(s) / len(s)
    x = [v - mean for v in s]
    rms = math.sqrt(sum(v * v for v in x) / len(x))
    r = w.getframerate()
    t = goertzel(x, f0, r)
    nb = sum(goertzel(x, f, r) for f in (700, 850, 1150, 1300)) / 4
    ratio = 10 * math.log10((t + 1e-9) / (nb + 1e-9))
    print(f"dc={mean:6.0f} rms={rms:7.1f} 1kHz={ratio:5.1f}dB")
    return ratio


def sweep(path, lo=100, hi=8000, step=50, top=6):
    """Print the strongest frequencies (coarse Goertzel sweep) in a recording."""
    w = wave.open(path)
    d = w.readframes(w.getnframes())
    s = struct.unpack("<%dh" % (len(d) // 2), d)[0::w.getnchannels()]
    r = w.getframerate()
    x = s[r // 4: r // 4 + r // 2]            # 0.5 s window after the start transient
    m = sum(x) / len(x); x = [v - m for v in x]
    p = sorted(((goertzel(x, f, r), f) for f in range(lo, hi, step)), reverse=True)[:top]
    tot = sum(goertzel(x, f, r) for f in range(lo, hi, step)) or 1
    print("peaks: " + ", ".join(f"{f}Hz {100*e/tot:.0f}%" for e, f in p))


if __name__ == "__main__":
    if sys.argv[1] == "analyze":
        analyze(sys.argv[2])
    elif sys.argv[1] == "sweep":
        sweep(sys.argv[2])
    else:
        rate = int(sys.argv[3]) if len(sys.argv) > 3 else RATE
        ch = int(sys.argv[4]) if len(sys.argv) > 4 else 2
        tone(float(sys.argv[1]), float(sys.argv[2]), rate=rate, ch=ch)

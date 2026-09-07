#!/usr/bin/env python3
"""Compare the RTL audio capture (audio.raw: 48 kHz s16le stereo) with
MAME's WAV: RMS levels, best-lag cross-correlation over the overlap, and a
WAV copy of the RTL audio for listening.
    wav_compare.py verif/board/out/audio.raw verif/golden/aburner2/mame.wav [--out rtl.wav] [--skip 0.2]"""
import argparse, wave
import numpy as np

def load_raw(p):
    d = np.frombuffer(open(p, "rb").read(), dtype="<i2")
    return d.reshape(-1, 2).astype(np.float64)

def load_wav(p):
    w = wave.open(p, "rb"); n = w.getnframes(); fr = w.getframerate(); ch = w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype="<i2").reshape(-1, ch).astype(np.float64)
    return d, fr

def highpass(x, fr, fc=20.0):
    a = np.exp(-2 * np.pi * fc / fr)
    y = np.empty_like(x); prev_y = 0.0; prev_x = 0.0
    for i in range(len(x)):
        prev_y = a * (prev_y + x[i] - prev_x); prev_x = x[i]; y[i] = prev_y
    return y


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw"); ap.add_argument("wav"); ap.add_argument("--out"); ap.add_argument("--skip", type=float, default=0.0); ap.add_argument("--min", type=float, default=0.9, help="envelope correlation to pass")
    a = ap.parse_args()
    r = load_raw(a.raw); m, fr = load_wav(a.wav)
    assert fr == 48000, fr
    s = int(a.skip * fr)
    r, m = r[s:], m[s:]
    n = min(len(r), len(m))
    print(f"rtl {len(r)/fr:.2f} s, mame {len(m)/fr:.2f} s, comparing {n/fr:.2f} s")
    rm, mm = r[:n].mean(axis=1), m[:n].mean(axis=1)
    print(f"rms rtl {np.sqrt((rm**2).mean()):.0f}  mame {np.sqrt((mm**2).mean()):.0f}")
    # first-order high-pass at 20 Hz on both: the PCM engines park voices on a
    # held byte (a DC level per voice, stepped when the driver rewrites its
    # volume), which is inaudible through any amplifier but dominated the
    # envelope of Enduro Racer's quieter passages, where the cue timing
    # differs by a few frames between the core and MAME (M8 finding)
    rm, mm = highpass(rm, fr), highpass(mm, fr)
    print(f"rms above 20 Hz: rtl {np.sqrt((rm**2).mean()):.0f}  mame {np.sqrt((mm**2).mean()):.0f}")
    if rm.std() > 0 and mm.std() > 0:
        best = (0, -1)
        for lag in range(-2400, 2401, 4):      # +-50 ms in 83 us steps
            x = rm[max(0, lag):n + min(0, lag)]; y = mm[max(0, -lag):n - max(0, lag)]
            k = min(len(x), len(y))
            c = np.corrcoef(x[:k], y[:k])[0, 1]
            if c > best[1]: best = (lag, c)
        print(f"best lag {best[0]/fr*1000:.1f} ms, sample correlation {best[1]:.3f}")
    # envelope correlation (5 ms RMS windows): robust to the phase/timing
    # differences between two FM implementations playing the same notes
    win = 240
    env = lambda x: np.sqrt((x[:len(x)//win*win].reshape(-1, win)**2).mean(axis=1))
    er, em = env(rm), env(mm)
    best_e = max(((np.corrcoef(er[max(0, l):len(er)+min(0, l)], em[max(0, -l):len(em)-max(0, l)])[0, 1], l) for l in range(-60, 61)))
    print(f"envelope correlation {best_e[0]:.3f} at lag {best_e[1]*5} ms")
    ok = best_e[0] >= a.min
    print("PASS" if ok else "FAIL")
    if a.out:
        w = wave.open(a.out, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
        w.writeframes(np.clip(r, -32768, 32767).astype("<i2").tobytes()); w.close()
    return 0 if ok else 1

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Record MAME's audio for the first N seconds to a WAV (48 kHz stereo).
    mame_wav.py aburner2 --seconds 4 --out verif/golden/aburner2/mame.wav"""
import argparse, os, subprocess, tempfile
ROMPATH = "/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set"); ap.add_argument("--seconds", type=int, default=4); ap.add_argument("--out", required=True)
    ap.add_argument("--coin", type=int, help="press Coin 1 at this frame (tools/mame_coin.lua)")
    ap.add_argument("--start", type=int, help="press 1P Start at this frame (needs --coin)")
    a = ap.parse_args()
    out = os.path.abspath(a.out)
    env = dict(os.environ)
    cmd = [os.environ.get("MAME_BIN", "mame"), a.set, "-rompath", ROMPATH, "-window", "-nothrottle", "-skip_gameinfo",
           "-samplerate", "48000", "-wavwrite", out, "-seconds_to_run", str(a.seconds),
           "-nvram_directory", tempfile.mkdtemp(), "-cfg_directory", tempfile.mkdtemp()]
    if a.coin is not None:
        env["SH_COIN"] = str(a.coin)
        if a.start is not None:
            env["SH_START"] = str(a.start)
        cmd += ["-autoboot_script", os.path.join(os.path.dirname(os.path.abspath(__file__)), "mame_coin.lua")]
    subprocess.run(cmd, env=env, check=False)
    print(out, os.path.getsize(out) if os.path.exists(out) else "missing")

if __name__ == "__main__":
    main()

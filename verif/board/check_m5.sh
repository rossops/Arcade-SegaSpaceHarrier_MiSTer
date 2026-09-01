#!/bin/sh
# M5 gate: the YM2203 sound board. The 315-5218 stays exact against its
# model (cocotb, BANK_512 at this board's configuration); the board's
# audio over 10 seconds of the attract sequence must correlate with
# MAME's recording on the 5 ms envelope (threshold 0.9 inside
# wav_compare; the parents passed around 0.96, and the FM phase makes
# sample-level correlation meaningless). No coin: the attract theme is
# a one-shot whose ending exercises the driver's end-of-song path, and
# a coin during it lands the sound driver's internal channel race on
# the opposite side from MAME (see DESIGN.md M5 findings) — the
# no-coin run also matches the M4 video goldens, which the video
# recheck at frame 300 relies on. The video chain must stay
# pixel-exact with the sound section running.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"
G=verif/golden/hangon

sh verif/lint.sh
$PY -m pytest -q verif/unit/chips/test_segapcm.py
[ -f $G/main.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
[ -f $G/mame.wav ] || $PY tools/mame_wav.py hangon --seconds 10 --out $G/mame.wav

pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=600 DUMPFRAME=300 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 300
$PY tools/wav_compare.py verif/board/out/audio.raw $G/mame.wav --out verif/board/out/rtl.wav --skip 0.2

echo "M5 gate passed"

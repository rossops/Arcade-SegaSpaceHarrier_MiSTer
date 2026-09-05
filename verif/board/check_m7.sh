#!/bin/sh
# M7 gate: Space Harrier boots through its i8751 in the bench and the attract
# matches MAME layer by layer. Lint, the tool tests, then sharrier at frame
# 900 (MAME's capture; frame 300 is still the MCU's ROM checksum, black).
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/sharrier.zip"
G=verif/golden/sharrier

sh verif/lint.sh
$PY -m pytest -q tools/tests/
(cd verif/unit && ../.venv/bin/python -m pytest -q loader)   # the stream slot table, sh_pkg and the loader agree
[ -f $G/main.hex ] || $PY tools/pack_roms.py sharrier --zip "$ZIP" --out /dev/null --hexdir $G
for f in 900 1500 2400; do
    [ -f $G/f$f/frame.png ] || $PY tools/mame_capture.py sharrier --frame $f --out $G/f$f
done

pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run GAME=sharrier FRAMES=910 DUMPFRAME=900 PLUSARGS=+script=$PWD/verif/board/script_m7_stick.txt > verif/board/out/m7_run.log 2>&1
# the MCU must have interrupted the 68000 (IRQ 4), never collided with it on
# the bus, and never zeroed the heartbeat once the game was running (its two
# reset-time zero writes land around frame 17, long before)
grep -q "ipl=4" verif/board/out/m7_run.log || { echo "M7: the MCU never drove IRQ 4"; exit 1; }
grep -q "COLLISION" verif/board/out/m7_run.log && { echo "M7: a 68000 cycle started under an MCU grant"; exit 1; }
grep -E "MCU40385 f=[1-9][0-9][0-9]+" verif/board/out/m7_run.log && { echo "M7: the MCU wrote 40385 while the game ran"; exit 1; }
# the heartbeat must survive the MCU's reset zeros (dropped by the bridge): the
# MCU never gives up on it, and a stick deflected right and up after the frame-900
# dump reaches work RAM as 0x35 / 0xCB through the MCU's ADC loop
grep -q "MCUFALLBACK" verif/board/out/m7_run.log && { echo "M7: the MCU entered its heartbeat fallback"; exit 1; }
grep -E "MCUSTICK f=90[6-9] x=35 y=cb" verif/board/out/m7_run.log > /dev/null || { echo "M7: the deflected stick never reached 040492/3"; grep MCUSTICK verif/board/out/m7_run.log | tail -3; exit 1; }
# the layers from the RTL's own RAMs must compose to its frame, and the frame
# must equal MAME's capture within a few frames of drift (the MCU's checksum
# ends a handful of frames apart in the two: MAME's 900 was our 905)
$PY tools/board_check.py verif/board/out 900 sharrier
$PY tools/frame_diff.py verif/board/out $G/f900 --window 12 | tee /dev/stderr | grep -q "71680/71680 pixels equal" || { echo "M7: frame 900 differs from MAME"; exit 1; }

echo "M7 gate passed"

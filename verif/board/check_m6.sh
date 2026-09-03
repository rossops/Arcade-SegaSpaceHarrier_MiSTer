#!/bin/sh
# M6 gate: bring-up. The three Hang-On clone sets (hangon1, hangon2 with
# its own main+sub programs and the ride-on foot switches, the hangonvf
# bootleg with its redrawn art) each boot on the board and match their
# own MAME capture on every layer at frame 300; the MRA generator and
# stream stay in agreement for all four sets. The rest of the milestone
# is hardware-side and stays with the user: STA clean on the build
# (worst setup slack recorded in DESIGN.md), a 30-minute attract soak,
# and the control-feel checklist.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"

sh verif/lint.sh
$PY -m pytest -q tools/tests/

pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
for s in hangon1 hangon2 hangonvf; do
  G=verif/golden/$s
  [ -f $G/main.hex ] || $PY tools/pack_roms.py $s --zip "$ZIP" --out /dev/null --hexdir $G
  [ -d $G/f300 ] || $PY tools/mame_capture.py $s --frame 300 --out $G/f300
  make -C verif/board run GAME=$s FRAMES=310 DUMPFRAME=300 >/dev/null 2>&1
  $PY tools/board_check.py verif/board/out 300 $s
done

echo "M6 gate passed"

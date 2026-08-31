#!/bin/sh
# M3 gate: the road generator, three ways, on top of the M2 chain.
#  1. Model vs MAME: tools/model_check.py now composes road + tiles + text
#     and compares FULL frames. The remaining deficit on each capture is
#     sprite coverage (M4): thresholds sit just under the measured values,
#     whose diff maps are the logo/bike/roadside sprites (f300 is the title
#     screen behind the big HANG-ON logo sprite, hence 76).
#  2. RTL vs model: verif/unit/road/run_road.py replays each capture's road
#     RAM through the renderer under Icarus, every pixel and PLYCONT exact.
#  3. Board: tools/board_check.py with the road in the composition, frame
#     120 pixel-exact from the RTL's own dumps.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"
G=verif/golden/hangon

sh verif/lint.sh
[ -f $G/roadrom0.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
for f in f60 f150 f300 f900 f1500 f2400; do
  [ -d $G/$f ] || $PY tools/mame_capture.py hangon --frame ${f#f} --out $G/$f
done

echo "== model vs MAME captures (full frame; deficit = sprites, M4)"
check_pct() {
  pct=$($PY tools/model_check.py $G/$1 | sed -n 's/.*(\([0-9.]*\)%).*/\1/p' | head -1)
  echo "$1 ${pct}% (threshold $2)"
  [ "$(echo "$pct >= $2" | bc)" = "1" ]
}
check_pct f60 99.7
check_pct f150 94
check_pct f300 75
check_pct f900 100
check_pct f1500 97
check_pct f2400 93

echo "== road RTL vs model (Icarus)"
for f in f60 f150 f300 f900 f1500 f2400; do
  $PY verif/unit/road/run_road.py $G/$f >/dev/null || { echo "FAIL rtl $f"; exit 1; }
  echo "$f exact"
done

echo "== board"
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=122 DUMPFRAME=120 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 120

echo "M3 gate passed"

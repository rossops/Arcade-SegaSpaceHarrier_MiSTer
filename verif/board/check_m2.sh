#!/bin/sh
# M2 gate: the 315-5011/5012 tilemap chain, three ways.
#  1. Model vs MAME: tools/model_check.py renders the tile/text layers from
#     each MAME capture and every tile-opaque pixel must match MAME's PNG.
#     f2400 is in-game: sprites legitimately cover tile pixels there, so its
#     threshold is 87% (measured 87.58%, the diff map is the bike and the
#     roadside signs); every other capture must be 100%.
#  2. RTL vs model: verif/unit/tilemap/run_tilemap.py replays each capture
#     through the renderer under Icarus, pixel-exact per layer, plus a
#     synthetic run with row+column scroll asserted (no hangon capture ever
#     enables them; PPI port C bits 2:1 stay high).
#  3. Board: a 122-frame Verilator run, then tools/board_check.py renders
#     the model from the RTL's own +dumpframe RAM dumps and the whole
#     frame-120 PPM must match pixel for pixel.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"
G=verif/golden/hangon

sh verif/lint.sh
[ -f $G/main.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
[ -f $G/tilerom0.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
for f in f60 f150 f300 f900 f1500 f2400; do
  [ -d $G/$f ] || $PY tools/mame_capture.py hangon --frame ${f#f} --out $G/$f
done

echo "== model vs MAME captures"
for f in f60 f150 f300 f900 f1500; do
  $PY tools/model_check.py $G/$f | grep -q '(100.00%)' || { echo "FAIL model $f"; exit 1; }
  echo "$f 100%"
done
pct=$($PY tools/model_check.py $G/f2400 | sed -n 's/.*(\([0-9.]*\)%).*/\1/p' | head -1)
echo "f2400 ${pct}% (sprite-covered; threshold 87)"
[ "$(echo "$pct >= 87" | bc)" = "1" ]

echo "== RTL vs model (Icarus)"
for f in f60 f150 f300 f900 f1500 f2400; do
  $PY verif/unit/tilemap/run_tilemap.py $G/$f >/dev/null || { echo "FAIL rtl $f"; exit 1; }
  echo "$f exact"
done
$PY verif/unit/tilemap/run_tilemap.py $G/f2400 --synth >/dev/null || { echo "FAIL rtl synth"; exit 1; }
echo "synthetic row+column scroll exact"

echo "== board"
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=122 DUMPFRAME=120 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 120

echo "M2 gate passed"

#!/bin/sh
# M4 gate: the Hang-On sprite generator and the completed mixer. Full
# frames, nothing excluded, three ways.
#  1. Model vs MAME: tools/model_check.py composes every layer — tiles,
#     text, road, sprites, the shadow/hilight banks — and every capture
#     must match MAME's screenshot on all 71,680 pixels.
#  2. RTL vs model: verif/unit/sprite/run_sprite.py replays each capture's
#     sprite list through the renderer under Icarus, every pixel exact.
#  3. Board: tools/board_check.py from the RTL's own dumps (sprite RAM at
#     the renderer's line-260 copy moment, the rest at frame end), frame
#     300 pixel-exact.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"
G=verif/golden/hangon

sh verif/lint.sh
[ -f $G/zoomrom.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
for f in f60 f150 f300 f900 f1500 f2400; do
  [ -d $G/$f ] || $PY tools/mame_capture.py hangon --frame ${f#f} --out $G/$f
done

echo "== model vs MAME captures (full frame, every layer)"
for f in f60 f150 f300 f900 f1500 f2400; do
  $PY tools/model_check.py $G/$f | grep -q '(100.00%)' || { echo "FAIL model $f"; exit 1; }
  echo "$f 100%"
done

echo "== sprite RTL vs model (Icarus)"
for f in f60 f150 f300 f900 f1500 f2400; do
  $PY verif/unit/sprite/run_sprite.py $G/$f >/dev/null || { echo "FAIL rtl $f"; exit 1; }
  echo "$f exact"
done

echo "== board"
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=302 DUMPFRAME=300 >/dev/null 2>&1
$PY tools/board_check.py verif/board/out 300

echo "M4 gate passed"

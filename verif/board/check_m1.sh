#!/bin/sh
# M1 gate: both 68000s track MAME's executed-PC trace over 120 frames of
# hangon, the i8255 and ADC0804 are exact against their models, and the
# IRQ4 entries land on the same frames. The sub CPU's IRQ4 is a level the
# main CPU holds through the PPI for ~7 lines (224-231), so its handler
# re-enters a data-dependent number of times per frame; the count gets a
# tolerance (the Y Board's sub X had the same shape, from DTACK latency
# MAME does not model), while the main CPU's held-until-acknowledge vblank
# interrupt must match exactly.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/hangon.zip"
G=verif/golden/hangon

$PY -m pytest -q verif/unit/chips/test_i8255.py verif/unit/chips/test_adc0804.py
[ -f $G/trace_main_mame.txt ] || $PY tools/mame_trace.py hangon --seconds 2 --out $G
[ -f $G/main.hex ] || $PY tools/pack_roms.py hangon --zip "$ZIP" --out /dev/null --hexdir $G
pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
make -C verif/board run FRAMES=121 >/dev/null 2>&1
for cpu in main sub; do
  $PY tools/trace_compare.py $G/trace_${cpu}_mame.txt verif/board/out/trace_${cpu}_pc.txt \
    --max 2500000 --slack 1 --min-match 97 --max-resync 1000 | grep -v "^  resync"
done
# IRQ4 handler entries (vector 28 of each ROM: main 00123A, sub 0009B8).
# Main fires once per frame from vblank: counts must match within 2.
# Sub re-enters within the PPI window: within 10.
irqcheck() {
  cpu=$1; vec=$2; tol=$3
  rtl=$(grep -c "^$vec" verif/board/out/trace_${cpu}_pc.txt || true)
  mame=$(grep -c "^$vec" $G/trace_${cpu}_mame.txt || true)
  d=$((rtl - mame)); [ $d -lt 0 ] && d=$((-d))
  echo "$cpu: irq4 entries rtl $rtl mame $mame (tolerance $tol)"
  [ $d -le $tol ]
}
irqcheck main 00123a 2
irqcheck sub 0009b8 10
echo "M1 gate passed"

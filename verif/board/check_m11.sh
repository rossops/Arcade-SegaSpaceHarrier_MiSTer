#!/bin/sh
# M11 gate: Enduro Racer's CPU speed option. A race with the pedal held from
# the start, at the PCB's 10 MHz and at 20 MHz. MAME's zero-wait 68000
# updates 81 and 82 frames of 100 in the race's first two hundred frames
# and 99 after; the PCB-speed core drops at least as many, and the boosted
# core must update at least 98 of 100 in each of those windows with the
# sound handshake, the PCM engine and the watchdog undisturbed.
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/enduror.zip"
G=verif/golden/enduror
[ -f $G/main.hex ] || $PY tools/pack_roms.py enduror --zip "$ZIP" --out /dev/null --hexdir $G

pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
for cfg in "pcb 0" "boost 3"; do
    set -- $cfg
    make -C verif/board run GAME=enduror FRAMES=1410 DUMPFRAME=-1 COIN=700 PLUSARGS="+boost=$2 +script=$PWD/verif/board/script_m11_play.txt" > verif/board/out/m11_$1.log 2>&1
    grep -q "WATCHDOG\|Z80CRASH\|SNDOVR\|PCMLOST" verif/board/out/m11_$1.log && { echo "M11: $1 run reset, crashed or lost a byte"; exit 1; }
    grep -E "^CADENCE f=1[34]00 " verif/board/out/m11_$1.log | tee /dev/stderr | awk -v who=$1 '{split($4,a," "); n=$4} {print who, $2, "updated", $4}' > /dev/null
done
# the boosted run: at least 98 of 100 in 1200-1300 and 1300-1400
for f in 1300 1400; do
    N=$(grep -E "^CADENCE f=$f " verif/board/out/m11_boost.log | sed -E 's/.*updated ([0-9]+) of.*/\1/')
    [ "${N:-0}" -ge 98 ] || { echo "M11: boosted run updated $N of 100 frames ending at $f"; exit 1; }
done
echo "M11 gate passed"

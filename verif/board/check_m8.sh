#!/bin/sh
# M8 gate: Enduro Racer. enduror1 (the YM2203 board, FD1089B main CPU) and
# enduror (the YM2151 board) boot in the bench, compose from their own RAMs
# and match MAME's captures within a few frames of drift, and both sound
# boards' attract audio tracks MAME's recording. The decrypt itself is
# gated by its unit test against the Python model (which matches MAME's
# decrypted sets word for word).
set -e
cd "$(dirname "$0")/../.."
PY=verif/.venv/bin/python
ZIP="/Volumes/roms/Arcade/MAME 0.289 ROMs (merged)/enduror.zip"
MAME_REF=${MAME_REF:-$HOME/Code/mame-ref/hangon}

sh verif/lint.sh
$PY -m pytest -q tools/tests/
(cd verif/unit && ../.venv/bin/python -m pytest -q fd1089 loader)
for g in enduror1 enduror; do
    G=verif/golden/$g
    [ -f $G/main.hex ] || $PY tools/pack_roms.py $g --zip "$ZIP" --out /dev/null --hexdir $G
    for f in 300 600; do
        [ -f $G/f$f/frame.png ] || $PY tools/mame_capture.py $g --frame $f --out $G/f$f
    done
    # the audio reference comes from the reference MAME build (tools/mame_ref_build.sh:
    # 0.289 with the pre-0.289 loop-end rule, which stock 0.289 lacks and which this
    # game's engine loops need); without it the stock binary records and the gate
    # threshold drops, with the reason printed
    [ -f $G/mame_ref.wav ] || { [ -x "$MAME_REF" ] && MAME_BIN=$MAME_REF $PY tools/mame_wav.py $g --seconds 30 --out $G/mame_ref.wav; } || true
    [ -f $G/mame.wav ] || $PY tools/mame_wav.py $g --seconds 30 --out $G/mame.wav   # the attract is silent for its first 13 s
done

pkill -f Vtb_board 2>/dev/null || true
make -C verif/board build >/dev/null
for g in enduror1 enduror; do
    G=verif/golden/$g
    make -C verif/board run GAME=$g FRAMES=1810 DUMPFRAME=600 > verif/board/out/m8_$g.log 2>&1   # 30 s: the attract music starts at 13 s
    grep -q "WATCHDOG\|Z80CRASH\|COLLISION" verif/board/out/m8_$g.log && { echo "M8: $g reset, crashed or collided"; exit 1; }
    $PY tools/board_check.py verif/board/out 600 $g
    $PY tools/frame_diff.py verif/board/out $G/f600 --window 12 | tee /dev/stderr | grep -q "71680/71680 pixels equal" || { echo "M8: $g frame 600 differs from MAME"; exit 1; }
    # the YM2151 set scores 0.88 against the reference build: its engine loops
    # match register for register, but their volumes follow the demo bike's
    # speed, and the two demos are at different points of the race from about
    # 19 s on (the same drift Space Harrier's demo shows, docs/DESIGN.md M8);
    # 13-19 s scores 0.95 and above on both sets
    MIN=0.9; [ $g = enduror ] && MIN=0.85
    if [ -f $G/mame_ref.wav ]; then
        $PY tools/wav_compare.py verif/board/out/audio.raw $G/mame_ref.wav --out verif/board/out/rtl_$g.wav --skip 13 --min $MIN
    else
        echo "M8: no reference MAME build (tools/mame_ref_build.sh); comparing against stock 0.289, whose PCM silences this game's engine loops, at 0.7"
        $PY tools/wav_compare.py verif/board/out/audio.raw $G/mame.wav --out verif/board/out/rtl_$g.wav --skip 13 --min 0.7
    fi
done

# MAME's decrypted sets through a plain 68000 path must give the encrypted
# sets' frames: the decrypt in the core equals MAME's table from both sides
for pair in "endurord enduror" "enduror1d enduror1"; do
    set -- $pair
    [ -f verif/golden/$1/main.hex ] || $PY tools/pack_roms.py $1 --zip "$ZIP" --out /dev/null --hexdir verif/golden/$1
    make -C verif/board run GAME=$1 FRAMES=610 DUMPFRAME=600 > verif/board/out/m8_$1.log 2>&1
    $PY tools/frame_diff.py verif/board/out verif/golden/$2/f600 --window 12 | tee /dev/stderr | grep -q "71680/71680 pixels equal" || { echo "M8: $1 (decrypted) differs from $2"; exit 1; }
done

echo "M8 gate passed"

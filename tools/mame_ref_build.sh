#!/bin/sh
# Build the reference MAME for the audio gates: MAME 0.289 (the project's
# reference version) with one change, the 315-5218 loop-end rule MAME used
# through 0.288 restored in src/devices/sound/segapcm.cpp. 0.289's rewrite
# compares a voice's page against `end` itself; the Sega board plays Enduro
# Racer's engine loops (loop page == end page), which that rule silences
# (docs/DESIGN.md, M8). A driver-only build (segahang.cpp) of about 20
# minutes; the result lands at ~/Code/mame-ref/hangon (SUBTARGET names the binary) and the gates pick
# it up through MAME_REF. Needs the ~/Code/mame checkout with the mame0289
# tag fetched, and SDL3 plus pkgconf from Homebrew (brew install sdl3 pkgconf; the
# build links the library, not the framework).
set -e
SRC=${MAME_SRC:-$HOME/Code/mame}
DST=${MAME_REF_DIR:-$HOME/Code/mame-ref}
git -C "$SRC" fetch -q origin tag mame0289 2>/dev/null || true
[ -d "$DST" ] || git -C "$SRC" worktree add -q "$DST" mame0289
cd "$DST"
python3 - <<'PY'
p = "src/devices/sound/segapcm.cpp"; s = open(p).read()
old = "\t\tif ((addr >> 16) == end)\n"
new = "\t\tif ((addr >> 16) == uint8_t(end + 1))   // the rule through 0.288 (MiSTer core reference build)\n"
if old in s:
    open(p, "w").write(s.replace(old, new)); print("segapcm.cpp: end + 1 restored")
else:
    print("segapcm.cpp: already patched" if "uint8_t(end + 1)" in s else "segapcm.cpp: pattern not found")
PY
make -j8 SUBTARGET=hangon SOURCES=src/mame/sega/segahang.cpp REGENIE=1 NOWERROR=1 USE_LIBSDL=1
ls -la hangon

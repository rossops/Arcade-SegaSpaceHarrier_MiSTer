#!/bin/sh
# Verilator -Wall lint of every module we own (vendored code gets only the
# waivers it needs). Run from the repo root: sh verif/lint.sh
set -e
cd "$(dirname "$0")/.."
W="-Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-IMPORTSTAR -Wno-PINCONNECTEMPTY -DSH_Z80_TV80"
OWN="rtl/video/sh_video_timing.sv rtl/mem/sdram.sv rtl/mem/sh_rom_loader.sv rtl/mem/sh_dpram.sv \
  rtl/io/sh_ana_shape.sv rtl/io/sh_adc0804.sv \
  rtl/cpu/sh_rom_cache.sv rtl/audio/sh_segapcm_5218.sv rtl/video/sh_palette_5242.sv"
# sh_pkg.sv, sh_m68k_bus.sv and sh_soundsys.sv only lint inside a board top.
for f in $OWN; do
  verilator --lint-only $W -Irtl/video rtl/sh_pkg.sv $f --top-module $(basename ${f%.*}) >/dev/null
done
# board top with everything it instantiates (grow this list with the milestones)
verilator --lint-only $W -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Irtl/video \
  rtl/sh_pkg.sv rtl/video/sh_video_timing.sv rtl/sh_core.sv --top-module sh_core >/dev/null
echo "lint clean"

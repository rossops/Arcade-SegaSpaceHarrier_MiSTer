#!/bin/sh
# Verilator -Wall lint of every module we own (vendored code gets only the
# waivers it needs). Run from the repo root: sh verif/lint.sh
set -e
cd "$(dirname "$0")/.."
W="-Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT -Wno-IMPORTSTAR -Wno-PINCONNECTEMPTY -DYB_Z80_TV80"
OWN="rtl/video/sh_video_timing.sv rtl/mem/sdram.sv rtl/mem/sh_rom_loader.sv rtl/mem/sh_dpram.sv \
  rtl/cpu/sh_math_5248.sv rtl/cpu/sh_math_5249.sv rtl/io/sh_ana_shape.sv rtl/io/sh_315_5296.sv rtl/io/sh_msm6253.sv \
  rtl/cpu/sh_rom_cache.sv rtl/audio/sh_segapcm_5218.sv rtl/mem/sh_fb_if.sv rtl/video/sh_palette_5242.sv rtl/video/sh_ysprite_5305.sv rtl/video/sh_rotate_5306.sv rtl/video/sh_bsprite_5196.sv"
# sh_pkg.sv, sh_m68k_bus.sv and sh_soundsys.sv only lint inside a board top.
for f in $OWN; do
  verilator --lint-only $W -Irtl/video rtl/sh_pkg.sv $f --top-module $(basename ${f%.*}) >/dev/null
done
# board top with everything it instantiates (grow this list with the milestones)
verilator --lint-only $W -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Irtl/video -Irtl/cpu/fx68k verif/fx68k.vlt rtl/sh_pkg.sv rtl/video/sh_video_timing.sv rtl/mem/sh_dpram.sv \
  rtl/cpu/sh_math_5248.sv rtl/cpu/sh_math_5249.sv rtl/io/sh_ana_shape.sv rtl/io/sh_315_5296.sv rtl/io/sh_msm6253.sv \
  rtl/cpu/sh_rom_cache.sv rtl/cpu/sh_m68k_bus.sv rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/video/sh_palette_5242.sv rtl/mem/sh_fb_if.sv rtl/video/sh_ysprite_5305.sv rtl/video/sh_rotate_5306.sv rtl/video/sh_bsprite_5196.sv \
  rtl/audio/sh_segapcm_5218.sv rtl/audio/sh_soundsys.sv rtl/audio/jt51/*.v verif/board/tv80/*.v rtl/sh_core.sv --top-module sh_core >/dev/null
echo "lint clean"

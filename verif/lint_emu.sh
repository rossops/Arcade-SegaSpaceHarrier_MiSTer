#!/bin/sh
# Elaborate the MiSTer emu top against the real framework modules with
# Verilator. Catches port-list mismatches and multiply-driven nets that only
# Quartus would otherwise report (unlike verif/lint.sh this is not -Wall).
# Fails until rtl/sh_core.sv exists and Arcade-SegaSpaceHarrier.sv is trimmed to it.
set -e
cd "$(dirname "$0")/.."
verilator --lint-only -DSIMULATION --top-module emu -DYB_Z80_TV80 -Isys -Irtl/video \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT \
  -Wno-IMPORTSTAR -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
  -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-UNOPTFLAT \
  -Wno-CASEOVERLAP -Wno-LATCH -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-INITIALDLY \
  -Wno-ASCRANGE -Wno-LITENDIAN -Wno-PROCASSWIRE -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEX \
  verif/fx68k.vlt rtl/sh_pkg.sv rtl/video/sh_video_timing.sv rtl/mem/sdram.sv \
  rtl/mem/sh_rom_loader.sv rtl/mem/sh_dpram.sv rtl/cpu/sh_math_5248.sv rtl/cpu/sh_math_5249.sv \
  rtl/io/sh_ana_shape.sv rtl/io/sh_315_5296.sv rtl/io/sh_msm6253.sv rtl/cpu/sh_rom_cache.sv rtl/cpu/sh_m68k_bus.sv \
  rtl/audio/sh_segapcm_5218.sv rtl/audio/sh_soundsys.sv rtl/audio/jt51/*.v verif/board/tv80/*.v \
  rtl/mem/sh_fb_if.sv rtl/video/sh_palette_5242.sv rtl/video/sh_ysprite_5305.sv rtl/video/sh_rotate_5306.sv rtl/video/sh_bsprite_5196.sv \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv rtl/sh_core.sv rtl/pll.v \
  sys/hps_io.sv sys/arcade_video.v sys/video_freak.sv sys/scandoubler.v \
  sys/scanlines.v sys/gamma_corr.sv sys/video_cleaner.sv sys/video_mixer.sv \
  sys/hq2x.sv sys/math.sv sys/sys_top.v \
  Arcade-SegaSpaceHarrier.sv
echo "emu elaborates"

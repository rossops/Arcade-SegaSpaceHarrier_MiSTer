#!/bin/sh
# Elaborate the MiSTer emu top against the real framework modules with
# Verilator. Catches port-list mismatches and multiply-driven nets that only
# Quartus would otherwise report (unlike verif/lint.sh this is not -Wall).
set -e
cd "$(dirname "$0")/.."
verilator --lint-only -DSIMULATION --top-module emu -DSH_Z80_TV80 -Isys -Irtl/video -Irtl/cpu/fx68k \
  -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-PROCASSINIT \
  -Wno-IMPORTSTAR -Wno-WIDTH -Wno-PINCONNECTEMPTY -Wno-CASEINCOMPLETE \
  -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-UNOPTFLAT \
  -Wno-CASEOVERLAP -Wno-LATCH -Wno-SYNCASYNCNET -Wno-COMBDLY -Wno-INITIALDLY \
  -Wno-ASCRANGE -Wno-LITENDIAN -Wno-PROCASSWIRE -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEX \
  verif/fx68k.vlt rtl/sh_pkg.sv rtl/video/sh_video_timing.sv rtl/mem/sdram.sv \
  rtl/mem/sh_rom_loader.sv rtl/mem/sh_dpram.sv \
  rtl/io/sh_ana_shape.sv rtl/io/sh_adc0804.sv rtl/io/sh_i8255.sv rtl/cpu/sh_rom_cache.sv \
  rtl/cpu/sh_m68k_bus.sv rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/video/sh_palette_5242.sv rtl/video/sh_tilerom.sv rtl/video/sh_tilemap_5012.sv rtl/video/sh_roadrom.sv rtl/video/sh_road.sv rtl/video/sh_zoomrom.sv rtl/video/sh_sprite.sv \
  rtl/audio/sh_segapcm_5218.sv rtl/audio/sh_soundsys_2203.sv rtl/audio/jt03/*.v verif/board/tv80/*.v \
  rtl/sh_core.sv rtl/pll.v \
  sys/hps_io.sv sys/arcade_video.v sys/video_freak.sv sys/scandoubler.v \
  sys/scanlines.v sys/gamma_corr.sv sys/video_cleaner.sv sys/video_mixer.sv \
  sys/hq2x.sv sys/math.sv sys/sys_top.v \
  Arcade-SegaSpaceHarrier.sv
echo "emu elaborates"

# Verilator board simulation. From repo root: make -C verif/board run FRAMES=10
ROOT := $(abspath ../..)
SRCS := rtl/sh_pkg.sv rtl/video/sh_video_timing.sv rtl/mem/sh_dpram.sv \
  rtl/io/sh_ana_shape.sv rtl/io/sh_adc0804.sv rtl/io/sh_i8255.sv rtl/cpu/sh_rom_cache.sv rtl/cpu/sh_m68k_bus.sv \
  rtl/cpu/sh_mcu.sv rtl/cpu/jt8051/jt8051.v rtl/cpu/jt8051/jt8051_alu.v rtl/cpu/jt8051/jt8051_ctrl.v \
  rtl/cpu/jt8051/jt8051_periph.v rtl/cpu/jt8051/jt8051_regs.v rtl/cpu/jt8051/jt8051_serial.v \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/audio/sh_segapcm_5218.sv rtl/audio/sh_soundsys_2203.sv rtl/video/sh_palette_5242.sv \
  rtl/video/sh_tilerom.sv rtl/video/sh_tilemap_5012.sv rtl/video/sh_roadrom.sv rtl/video/sh_road.sv rtl/video/sh_zoomrom.sv rtl/video/sh_sprite.sv \
  rtl/sh_core.sv verif/board/sdram_model.sv verif/board/tb_board.sv
VFLAGS := -Wno-fatal -Wno-lint -Wno-style -Werror-PINMISSING -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
  -DSIMULATION --timing -O2 --x-assign fast --x-initial fast \
  --no-assert-case --top-module tb_board -I$(ROOT)/rtl/cpu/fx68k -I$(ROOT)/rtl/video -I$(ROOT)/rtl/cpu/jt8051
# Z80=tv80 (default): the core the DE10 runs. Z80=t80: the vendored T80 as the
# GHDL-converted netlist (verif/board/t80/gen.sh), the cross-check that showed
# the M6 sound crash was the T80's alone.
Z80 ?= tv80
ifeq ($(Z80),t80)
  VFLAGS += -DSH_Z80_T80
  Z80SRC := $(ROOT)/verif/board/t80/t80s.vlt $(ROOT)/verif/board/t80/T80s_ghdl.v $(wildcard $(ROOT)/verif/board/tv80/*.v)
else
  Z80SRC := $(wildcard $(ROOT)/verif/board/tv80/*.v)
endif
FRAMES ?= 10
DUMPFRAME ?= -1
COIN ?= -1
PLUSARGS ?=
GAME ?= hangon
# descriptor plusargs per set (tools/romsets.py); hangon-family sets need none
GAMEARGS_sharrier  := +game_id=1 +sharrier=1 +cpu10m=1 +mcu=1 +spr_banks=8 +adc_reverse=03 +ana_mode=1
GAMEARGS_sharrier1 := $(GAMEARGS_sharrier)
GAMEARGS := $(GAMEARGS_$(GAME))

EXTRA := $(wildcard $(ROOT)/rtl/audio/jt51/*.v) $(wildcard $(ROOT)/rtl/audio/jt03/*.v) $(Z80SRC)

obj_dir/Vtb_board: $(addprefix $(ROOT)/,$(SRCS)) $(EXTRA) main.cpp
	verilator $(VFLAGS) --cc --exe --build -j 4 $(addprefix $(ROOT)/,$(SRCS)) $(EXTRA) main.cpp -o Vtb_board

build: obj_dir/Vtb_board

# the SDRAM model reads verif/golden/$(GAME)/<region>.hex (tools/pack_roms.py --hexdir)
# the share keep-alive (tools/keepalive.sh) runs for the duration of every run
run: obj_dir/Vtb_board
	mkdir -p out/verif && rm -f out/frame_*.ppm && ln -sfn $(ROOT)/verif/golden out/verif/golden; \
	ln -sf $(ROOT)/rtl/cpu/fx68k/microrom.mem out/microrom.mem; ln -sf $(ROOT)/rtl/cpu/fx68k/nanorom.mem out/nanorom.mem; \
	for p in 0 1 2; do ln -sf $(ROOT)/verif/golden/$(GAME)/tilerom$$p.hex out/tilerom$$p.hex; done; \
	for p in 0 1; do ln -sf $(ROOT)/verif/golden/$(GAME)/roadrom$$p.hex out/roadrom$$p.hex; done; \
	ln -sf $(ROOT)/verif/golden/$(GAME)/zoomrom.hex out/zoomrom.hex; \
	rm -f out/z80rom.hex && head -16384 $(ROOT)/verif/golden/$(GAME)/z80.hex > out/z80rom.hex; \
	rm -f out/mcurom.hex; [ -f $(ROOT)/verif/golden/$(GAME)/mcu.hex ] && head -2048 $(ROOT)/verif/golden/$(GAME)/mcu.hex > out/mcurom.hex || true; \
	ln -sf $(ROOT)/rtl/cpu/jt8051/jt8051.uc out/jt8051.uc; \
	sh $(ROOT)/tools/keepalive.sh $(ROOT) & KA=$$!; \
	(cd out && ../obj_dir/Vtb_board +frames=$(FRAMES) +dumpframe=$(DUMPFRAME) +coin=$(COIN) +hexdir=verif/golden/$(GAME) +tilerom +roadrom +zoomrom +z80rom +mcurom $(GAMEARGS) $(PLUSARGS)); RC=$$?; \
	kill $$KA 2>/dev/null; wait $$KA 2>/dev/null; exit $$RC

clean:
	rm -rf obj_dir out

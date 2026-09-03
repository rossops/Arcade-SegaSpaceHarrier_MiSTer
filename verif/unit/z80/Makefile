# Standalone Z80 NMI test: make -C verif/unit/z80 run [Z80=tv80] [BUSY=<ns>]
ROOT := $(abspath ../../..)
Z80 ?= t80
BUSY ?= 1000000000
NMI_AT ?= 200000
ifeq ($(Z80),tv80)
  SRC := $(wildcard $(ROOT)/verif/board/tv80/*.v)
  DEF := -DSH_Z80_TV80
else
  # (the unit benches keep their own SH_Z80_TV80 switch: tv80s on a derived clock vs the T80s netlist)
  SRC := $(ROOT)/verif/board/t80/t80s.vlt $(ROOT)/verif/board/t80/T80s_ghdl.v
  DEF :=
endif
run:
	verilator -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN --timing --binary -j 4 $(DEF) --Mdir obj_$(Z80) --top-module tb_z80_nmi tb_z80_nmi.sv $(SRC) -o Vtb >/dev/null
	./obj_$(Z80)/Vtb +busy=$(BUSY) +nmi_at=$(NMI_AT)

build:
	verilator -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN --timing --binary -j 4 $(DEF) --Mdir obj_$(Z80) --top-module tb_z80_nmi tb_z80_nmi.sv $(SRC) -o Vtb >/dev/null

SECONDS ?= 10
latch:
	verilator -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN --timing --binary -j 4 $(DEF) --Mdir objl_$(Z80) --top-module tb_z80_latch tb_z80_latch.sv $(SRC) -o Vtb >/dev/null
	./objl_$(Z80)/Vtb +seconds=$(SECONDS)

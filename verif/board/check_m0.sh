#!/bin/sh
# M0 gate: the trimmed scaffold lints, the emu top elaborates, the video
# timing smoke test passes, the carried chip tests still pass, the board
# bench builds, and the MRA/stream tools agree with each other and with
# MAME's CRCs (the ROM-dependent cases need the hangon zip; they skip
# without it, so run this on the Mac with the ROM share mounted).
# The other half of the M0 pass criterion — the Quartus fit of the stub
# with clean STA and the M10K baseline — runs on the Windows box.
set -e
cd "$(dirname "$0")/../.."

sh verif/lint.sh
sh verif/lint_emu.sh

iverilog -g2012 -o verif/unit/sim_build_tb_timing.vvp \
  rtl/sh_pkg.sv rtl/video/sh_video_timing.sv verif/unit/timing/tb_timing.sv
vvp verif/unit/sim_build_tb_timing.vvp | grep -q '^PASS$'
rm -f verif/unit/sim_build_tb_timing.vvp
echo "timing smoke test passed"

(cd verif/unit && ../.venv/bin/python -m pytest -q chips/)

make -C verif/board build >/dev/null
echo "board bench builds"

verif/.venv/bin/python -m pytest -q tools/tests

echo "M0 gate green (Quartus fit still to be checked on the build box)"

#!/bin/sh
# jt8051 comes from jotego/jtcores (modules/jt8051, GPL-3.0-or-later), commit
# 62cacc840340ad1fe7d6be481d0f9bbebe835e7d (2026-09-01). The hdl/*.v files are
# vendored as they are; jt8051.vh and jt8051_param.vh are generated from
# ucode/8051.yaml (kept here as 8051.yaml) by jtframe's ucode tool:
#
#   go build -o jtframe_bin ./modules/jtframe/src/jtframe        (in a jtcores checkout)
#   export JTFRAME=.../modules/jtframe JTROOT=... CORES=.../cores MODULES=.../modules JTBIN=/tmp/jtbin
#   cd modules/jt8051 && jtframe_bin ucode --output jt8051 jt8051 8051
#
# which writes jt8051.vh, jt8051_param.vh (and a jt8051.uc listing). Copy the
# two .vh files here when the YAML or the tool changes.
echo "see the comment: the microcode is generated in a jtcores checkout with jtframe ucode"

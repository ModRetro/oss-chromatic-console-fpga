#!/bin/sh
set -eu
cd "$(dirname "$0")"
# Set GOWIN_SH to the installed gw_sh executable, or put it on PATH.
"${GOWIN_SH:-gw_sh}" build.tcl
mkdir -p build
cp impl/pnr/evt1_x2.fs build/evt1_x2.fs
cp impl/pnr/evt1_x2.bin build/evt1_x2.bin

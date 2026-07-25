#!/bin/sh
set -eu

PREFIX=${PREFIX:-/usr/local}
rm -f "$PREFIX/bin/zstd-splitter"
rm -f "$PREFIX/share/man/man1/zstd-splitter.1.gz"
printf 'Removed zstd-splitter from %s\n' "$PREFIX"

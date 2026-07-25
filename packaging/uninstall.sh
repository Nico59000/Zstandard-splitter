#!/bin/sh
set -eu
PREFIX=${PREFIX:-/usr/local}
rm -f "$PREFIX/bin/zstd-splitter" "$PREFIX/share/man/man1/zstd-splitter.1.gz"
rm -rf "$PREFIX/share/doc/zstd-splitter"
printf 'Removed zstd-splitter from %s\n' "$PREFIX"

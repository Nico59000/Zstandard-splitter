#!/bin/sh
set -eu

PREFIX=${PREFIX:-/usr/local}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINDIR=$PREFIX/bin
MANDIR=$PREFIX/share/man/man1

mkdir -p "$BINDIR" "$MANDIR"
install -m 0755 "$SCRIPT_DIR/src/zstd-splitter.sh" "$BINDIR/zstd-splitter"
install -m 0644 "$SCRIPT_DIR/man/man1/zstd-splitter.1.gz" \
    "$MANDIR/zstd-splitter.1.gz"

printf 'Installed %s\n' "$BINDIR/zstd-splitter"
printf 'Installed %s\n' "$MANDIR/zstd-splitter.1.gz"

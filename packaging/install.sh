#!/bin/sh

set -eu

PREFIX=${PREFIX:-/usr/local}
DESTDIR=${DESTDIR:-}
PACKAGE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINDIR=$DESTDIR$PREFIX/bin
MANDIR=$DESTDIR$PREFIX/share/man/man1

mkdir -p "$BINDIR" "$MANDIR"
install -m 0755 "$PACKAGE_ROOT/src/zstd-splitter.sh" "$BINDIR/zstd-splitter"
install -m 0644 "$PACKAGE_ROOT/man/man1/zstd-splitter.1.gz" "$MANDIR/zstd-splitter.1.gz"

printf '%s\n' "Installed: $BINDIR/zstd-splitter"
printf '%s\n' "Installed: $MANDIR/zstd-splitter.1.gz"

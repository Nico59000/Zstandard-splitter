#!/bin/sh

set -eu

PREFIX=${PREFIX:-/usr/local}
DESTDIR=${DESTDIR:-}
BINARY=$DESTDIR$PREFIX/bin/zstd-splitter
MANPAGE=$DESTDIR$PREFIX/share/man/man1/zstd-splitter.1.gz

rm -f "$BINARY" "$MANPAGE"
printf '%s\n' "Removed: $BINARY"
printf '%s\n' "Removed: $MANPAGE"

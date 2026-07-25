#!/bin/sh
set -eu
PREFIX=${PREFIX:-/usr/local}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
install -d "$PREFIX/bin" "$PREFIX/share/man/man1" "$PREFIX/share/doc/zstd-splitter"
install -m 0755 "$SCRIPT_DIR/src/zstd-splitter.sh" "$PREFIX/bin/zstd-splitter"
install -m 0644 "$SCRIPT_DIR/man/man1/zstd-splitter.1.gz" "$PREFIX/share/man/man1/zstd-splitter.1.gz"
install -m 0644 "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/docs/NETWORK-OPTIONS.md" "$SCRIPT_DIR/docs/SECURITY.md" "$PREFIX/share/doc/zstd-splitter/"
printf 'Installed zstd-splitter under %s\n' "$PREFIX"

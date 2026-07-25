#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SCRIPT=$ROOT/src/zstd-splitter.sh
sh -n "$SCRIPT"
"$SCRIPT" --version
"$SCRIPT" -h >/dev/null
"$SCRIPT" -E >/dev/null
if command -v zstd >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1; then
  TMP=${TMPDIR:-/tmp}/zstd-splitter-smoke.$$
  trap 'rm -rf "$TMP"' 0 1 2 3 15
  mkdir -p "$TMP/source/sub"
  printf 'alpha\n' >"$TMP/source/a file.txt"
  printf 'beta\n' >"$TMP/source/sub/b.txt"
  "$SCRIPT" -c -i -s 1K "$TMP/source" >/dev/null
  "$SCRIPT" -v -i "$TMP/source.tar.zst.part.aaaaaa" >/dev/null
  "$SCRIPT" -x -i -f -d "$TMP/restored" "$TMP/source.tar.zst.part.aaaaaa" >/dev/null
  cmp "$TMP/source/a file.txt" "$TMP/restored/source/a file.txt"
fi
printf 'smoke test passed\n'

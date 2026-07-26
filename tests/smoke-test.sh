#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROGRAM=$SCRIPT_DIR/src/zstd-splitter.sh

for command_name in zstd sha256sum cmp readlink tar split
 do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'SKIP: missing command: %s\n' "$command_name"
        exit 0
    fi
 done

TMP_PARENT=${TMPDIR:-/tmp}
TEST_DIR=$TMP_PARENT/zstd-splitter-test.$$
trap 'rm -rf "$TEST_DIR"' 0 1 2 3 15
mkdir -p "$TEST_DIR/source/sub" "$TEST_DIR/source/empty"
printf 'alpha\n' > "$TEST_DIR/source/a file.txt"
printf 'beta\n' > "$TEST_DIR/source/sub/b.txt"
ln -s sub/b.txt "$TEST_DIR/source/link"

"$PROGRAM" -c -i -s 32 -f "$TEST_DIR/source"
PART=$TEST_DIR/source.tar.zst.part.aaaaaa
"$PROGRAM" -v -i "$PART"
"$PROGRAM" -j -i -f "$PART"
"$PROGRAM" -x -i -f -d "$TEST_DIR/restored" "$TEST_DIR/source.tar.zst"
cmp "$TEST_DIR/source/a file.txt" "$TEST_DIR/restored/source/a file.txt"
cmp "$TEST_DIR/source/sub/b.txt" "$TEST_DIR/restored/source/sub/b.txt"

printf 'PASS: strict compression, split, verification, join, and extraction\n'

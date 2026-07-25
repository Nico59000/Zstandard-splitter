#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SCRIPT=$ROOT/src/zstd-splitter.sh
"$SCRIPT" -Q config -O dry-run=yes >/dev/null
"$SCRIPT" -Q network -R example.invalid:/srv/backups -O dry-run=yes >/dev/null
printf 'network dry-run test passed\n'

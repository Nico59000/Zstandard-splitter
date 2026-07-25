#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SCRIPT=$ROOT/src/zstd-splitter.sh
TMP=${TMPDIR:-/tmp}/zstd-splitter-mock-network.$$
MOCK=$TMP/bin
REMOTE=$TMP/remote
DATA=$TMP/data
trap 'rm -rf "$TMP"' 0 1 2 3 15
mkdir -p "$MOCK" "$REMOTE" "$DATA/source/sub"
cat >"$MOCK/ssh" <<'PYSSH'
#!/usr/bin/env python3
import subprocess, sys
raise SystemExit(subprocess.call(['/bin/sh','-c',sys.argv[-1]], stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr))
PYSSH
cat >"$MOCK/sftp" <<'PYSFTP'
#!/usr/bin/env python3
import os, shlex, shutil, sys
args=sys.argv[1:]; batch=None; i=0
while i < len(args):
    if args[i] == '-b': batch=args[i+1]; i += 2
    elif args[i] in ('-B','-R','-l','-P','-i','-J','-o'): i += 2
    else: i += 1
if not batch: raise SystemExit(2)
for raw in open(batch, encoding='utf-8'):
    p=shlex.split(raw.strip())
    if not p: continue
    cmd=p[0]; j=1
    if j < len(p) and p[j] == '-a': j += 1
    src,dst=p[j],p[j+1]
    os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
    shutil.copyfile(src,dst)
PYSFTP
chmod +x "$MOCK/ssh" "$MOCK/sftp"
printf 'alpha\n' >"$DATA/source/a file.txt"
printf 'beta\n' >"$DATA/source/sub/b.txt"
"$SCRIPT" -c -i -s 16K "$DATA/source" >/dev/null
PATH="$MOCK:$PATH" "$SCRIPT" -P -i -R mock:"$REMOTE" -O remote-fsync=no -O remote-verify=archive "$DATA/source.tar.zst.part.aaaaaa" >/dev/null
BUNDLE=$REMOTE/source.tar.zst.bundle
test -f "$BUNDLE/source.tar.zst.manifest.sha256"
mkdir -p "$DATA/pulled"
PATH="$MOCK:$PATH" "$SCRIPT" -G -i -R mock:"$BUNDLE/source.tar.zst.part.aaaaaa" -d "$DATA/pulled" -O remote-fsync=no >/dev/null
"$SCRIPT" -v -i "$DATA/pulled/source.tar.zst.part.aaaaaa" >/dev/null
printf 'mock SSH/SFTP integration test passed\n'

# zstd-splitter 3.0

`zstd-splitter.sh` creates a tar stream, compresses it with a selectable
stream-compression engine, divides it into parts, reconstructs those parts,
and extracts the resulting archive.

Version 3.0 adds an optional strict SHA-256 integrity layer covering the source
content, the complete compressed archive, and every split part.

Despite its historical name, the program supports Zstandard, gzip, bzip2, xz,
LZMA, lzip, lzop, and LZ4 when the corresponding external tools are installed.
Zstandard remains the default.

## Main features

- POSIX `/bin/sh` implementation and `getopts` command-line processing.
- Interactive terminal menu when launched without arguments.
- Streaming `tar -> compressor -> split` processing.
- Native compressed-stream verification for every supported engine.
- Optional strict SHA-256 manifest selected with `-i`.
- Reconstruction from any member of a part set.
- Direct extraction from either a complete archive or any split part.
- Post-extraction comparison against the original source inventory.
- Detection of source changes during strict compression.

## Installation

```sh
sudo sh packaging/install.sh
```

The default installation paths are:

```text
/usr/local/bin/zstd-splitter
/usr/local/share/man/man1/zstd-splitter.1.gz
```

An alternate prefix can be supplied:

```sh
sudo PREFIX=/opt/zstd-splitter sh packaging/install.sh
```

## Basic use

Display help and supported engines:

```sh
zstd-splitter -h
zstd-splitter -E
man zstd-splitter
```

Compress and split with Zstandard:

```sh
zstd-splitter -c -s 500M "/path/My directory"
```

Create strict SHA-256 metadata:

```sh
zstd-splitter -c -i -s 500M "/path/My directory"
```

This produces parts such as:

```text
My directory.tar.zst.part.aaaaaa
My directory.tar.zst.part.aaaaab
```

and the sidecar manifest:

```text
My directory.tar.zst.manifest.sha256
```

Strictly verify a part set without publishing a reconstructed archive:

```sh
zstd-splitter -v -i "My directory.tar.zst.part.aaaaab"
```

Strictly reconstruct the complete archive:

```sh
zstd-splitter -j -i "My directory.tar.zst.part.aaaaab"
```

Strictly reconstruct, extract, and validate the restored source tree:

```sh
zstd-splitter -x -i -d restored \
  "My directory.tar.zst.part.aaaaab"
```

Extract an already reconstructed archive:

```sh
zstd-splitter -x -i -d restored "My directory.tar.zst"
```

## Strict integrity model

The `-i` option creates or requires a sidecar manifest with three layers:

1. **Source tree** — a canonical inventory records each regular file, directory,
   and symbolic link. Regular-file content is SHA-256 hashed. Symbolic-link
   targets are SHA-256 hashed. Empty directories and path structure are retained.
   The inventory itself receives an aggregate SHA-256 digest.
2. **Compressed archive** — the complete compressed byte stream receives a
   SHA-256 digest and byte count.
3. **Split parts** — every part receives its own SHA-256 digest and byte count.

During strict compression the source inventory is generated both before and
after archiving. If it changed during the operation, the parts and manifest are
not published.

During strict extraction, the program extracts into a dedicated directory,
regenerates the canonical inventory, and compares both its aggregate digest and
its complete records with the original manifest.

The source-tree digest covers content, object type, symlink target, empty
directories, and relative paths. It intentionally does **not** claim to cover
ownership, permissions, timestamps, ACLs, extended attributes, sparse-file
layout, or filesystem-specific metadata. SHA-256 manifests detect accidental
corruption; they are not digital signatures and do not authenticate a manifest
against deliberate replacement.

See [`docs/INTEGRITY-MANIFEST.md`](docs/INTEGRITY-MANIFEST.md) for the format.

## Dependencies

Base operation requires common Unix tools plus `tar` and `split`. Each selected
compression engine requires its own command.

Strict mode additionally requires:

```text
sha256sum
cmp
readlink
```

The SHA-256 command name follows the GNU/Coreutils convention. Systems exposing
SHA-256 under a different utility name need a compatibility wrapper.

## Verification of this package

From the package root:

```sh
sha256sum -c checksums/SHA256SUMS
sh tests/smoke-test.sh
```

The smoke test runs only when `zstd` and the strict-integrity dependencies are
available.

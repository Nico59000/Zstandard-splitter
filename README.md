# Zstandard-splitter
The posix zstd-splitter 
# zstd-splitter

`zstd-splitter` is a POSIX `/bin/sh` utility that creates a tar stream, compresses it with a selectable compression engine, splits the compressed stream into parts, and later joins and verifies those parts.

Zstandard is the default engine. The script can also use gzip, bzip2, xz, lzma, lzip, lzop, or lz4 when the corresponding external command is installed.

## Package layout

```text
zstd-splitter-2.0/
├── README.md
├── VERSION
├── TREE.txt
├── src/
│   └── zstd-splitter.sh
├── man/
│   └── man1/
│       ├── zstd-splitter.1
│       └── zstd-splitter.1.gz
├── docs/
│   ├── BUILTIN_HELP.txt
│   └── ENGINES.txt
├── examples/
│   └── commands.md
├── packaging/
│   ├── install.sh
│   └── uninstall.sh
└── checksums/
    └── SHA256SUMS
```

## Requirements

Required base commands:

- a POSIX-compatible `/bin/sh`;
- `tar`, `split`, `cat`, `mkdir`, `rm`, `mv`, `dirname`, `basename`, `mkfifo`, and `awk`;
- at least one supported compression command.

Compression commands are external dependencies:

| Engine | Command | Archive extension | Thread option |
|---|---|---|---|
| zstd | `zstd` | `.tar.zst` | yes |
| gzip | `gzip` | `.tar.gz` | no |
| bzip2 | `bzip2` | `.tar.bz2` | no |
| xz | `xz` | `.tar.xz` | yes |
| lzma | `xz` | `.tar.lzma` | yes |
| lzip | `lzip` | `.tar.lz` | no |
| lzop | `lzop` | `.tar.lzo` | no |
| lz4 | `lz4` | `.tar.lz4` | no |

## Quick start

Display the built-in help:

```sh
sh src/zstd-splitter.sh -h
```

List compression engines:

```sh
sh src/zstd-splitter.sh -E
```

Compress and split with the default Zstandard engine:

```sh
sh src/zstd-splitter.sh -c -s 500M "/path/My directory"
```

Compress with xz:

```sh
sh src/zstd-splitter.sh -c -e xz -s 2GiB -l 6 -T 0 source-directory
```

Join a part set by naming any one of its parts:

```sh
sh src/zstd-splitter.sh -j archive.tar.zst.part.aaaaaa
```

Use `-f` to replace an existing output without an interactive confirmation.

## Installation

Install under `/usr/local` by default:

```sh
sudo sh packaging/install.sh
```

Choose another prefix:

```sh
sudo PREFIX=/opt/zstd-splitter sh packaging/install.sh
```

The default installation creates:

```text
/usr/local/bin/zstd-splitter
/usr/local/share/man/man1/zstd-splitter.1.gz
```

After installation:

```sh
zstd-splitter -h
man zstd-splitter
```

If the manual-page database is used on the target system, refresh it with `mandb` when necessary.

## Uninstallation

```sh
sudo sh packaging/uninstall.sh
```

Use the same `PREFIX` value that was used during installation.

## Documentation

- `docs/BUILTIN_HELP.txt` is a captured copy of the script's internal help.
- `docs/ENGINES.txt` is a captured list of supported engines.
- `man/man1/zstd-splitter.1` is the editable roff manual page.
- `man/man1/zstd-splitter.1.gz` is ready for installation.
- `examples/commands.md` contains command-line examples.

## Integrity

Verify the package files from the package root:

```sh
sha256sum -c checksums/SHA256SUMS
```

The checksum list intentionally excludes itself.

## Portability notes

The script uses POSIX shell syntax and `getopts` for short options. Compression programs and several practical utilities are external to POSIX. The convenience aliases `--help` and `--engines`, binary-size suffixes such as `GiB`, and some compressor-specific options are extensions documented by the script and manual page.

No software license has been assigned in this package. Distribution and reuse terms must be defined by the copyright holder before public release.

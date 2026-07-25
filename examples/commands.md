# Command examples

## Non-strict compatibility mode

```sh
zstd-splitter -c -s 500M source-directory
zstd-splitter -j source-directory.tar.zst.part.aaaaaa
zstd-splitter -x -d restored source-directory.tar.zst
```

## Strict Zstandard workflow

```sh
zstd-splitter -c -i -s 500M source-directory
zstd-splitter -v -i source-directory.tar.zst.part.aaaaab
zstd-splitter -j -i source-directory.tar.zst.part.aaaaab
zstd-splitter -x -i -d restored source-directory.tar.zst
```

## Strict extraction directly from parts

```sh
zstd-splitter -x -i -d restored \
  source-directory.tar.zst.part.aaaaab
```

The selected part does not need to be the first part.

## Other compression engines

```sh
zstd-splitter -c -i -e gzip  -l 9 -s 100M source-directory
zstd-splitter -c -i -e bzip2 -l 9 -s 100M source-directory
zstd-splitter -c -i -e xz    -l 6 -T 0 -s 1GiB source-directory
zstd-splitter -c -i -e lzma  -l 6 -T 0 -s 1GiB source-directory
zstd-splitter -c -i -e lzip  -l 6 -s 100M source-directory
zstd-splitter -c -i -e lzop  -l 3 -s 100M source-directory
zstd-splitter -c -i -e lz4   -l 1 -s 100M source-directory
```

## Explicit manifest path

```sh
zstd-splitter -v -i -m /trusted/manifests/archive.manifest.sha256 \
  archive.tar.zst.part.aaaaaa
```

## Replace existing outputs

```sh
zstd-splitter -j -i -f archive.tar.zst.part.aaaaaa
zstd-splitter -x -i -f -d restored archive.tar.zst
```

With extraction, `-f` removes and recreates the destination directory. Review
the destination carefully before using this option.

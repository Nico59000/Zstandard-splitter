# Command examples

The examples assume either installation as `zstd-splitter` or execution from the package root as `sh src/zstd-splitter.sh`.

## Help and engine discovery

```sh
zstd-splitter -h
zstd-splitter -E
```

## Compress and split

Default Zstandard compression:

```sh
zstd-splitter -c -s 500M "/data/My directory"
```

Gzip with compression level 9:

```sh
zstd-splitter -c -e gzip -s 100M -l 9 disk-image.raw
```

Xz with automatic worker selection:

```sh
zstd-splitter -c -e xz -s 2GiB -l 6 -T 0 source-directory
```

Force replacement of an existing part set:

```sh
zstd-splitter -c -f -s 500M source-directory
```

Protect a source pathname beginning with a hyphen:

```sh
zstd-splitter -c -s 100M -- "-source-file"
```

## Join and verify

Any member of a part set may be supplied:

```sh
zstd-splitter -j archive.tar.zst.part.aaaaac
zstd-splitter -j archive.tar.gz.part.aaaaaa
zstd-splitter -j archive.tar.xz.part.aaaaab
```

Force replacement of an existing reconstructed archive:

```sh
zstd-splitter -j -f archive.tar.zst.part.aaaaaa
```

## Interactive mode

Run without arguments:

```sh
zstd-splitter
```

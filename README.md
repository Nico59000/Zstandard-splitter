# zstd-splitter 4.1

`zstd-splitter` is a POSIX `/bin/sh` tar compression, splitting, integrity and SSH transfer utility. Version 4.1 is the corresponding cumulative milestone in the 4.x Network Swiss-Knife programme.

## Release capabilities

- All 4.0 features.
- Network profiles: safe, LAN, jumbo-LAN, WAN, high-latency, metered, unstable and archive.
- Parallel SFTP part transfers.
- SFTP buffer/request tuning and bandwidth caps.
- Non-destructive route, MTU and jumbo-frame diagnostics.
- SSH connection multiplexing and tuning recommendations.

## Security model

Network publication is strict by default. A transfer uses the version 3 SHA-256 manifest, verifies every part after upload, reconstructs and checks the compressed archive remotely, and publishes a completed bundle only after validation. Remote paths must be absolute. Host-key checking defaults to `strict`; forwarding and interactive authentication are not enabled by the script.

The tool does not modify interface MTUs, TCP sysctls, congestion-control algorithms or firewall policy. Jumbo-frame support is diagnostic and tuning-oriented only.

## Core examples

```sh
# Compress locally and publish transactionally
zstd-splitter -c -i -s 1G -R backup@nas:/srv/backups /srv/data

# Push an existing strict part set
zstd-splitter -P -i -R backup@nas:/srv/backups data.tar.zst.part.aaaaaa

# Pull and verify a remote part set
zstd-splitter -G -i -R backup@nas:/srv/backups/data.tar.zst.bundle/data.tar.zst.part.aaaaaa -d ./download

# Network preflight
zstd-splitter -Q network -R backup@nas:/srv/backups
```

## Configuration

Use repeated `-O NAME=VALUE` options or a file passed with `-F FILE`. See `docs/NETWORK-OPTIONS.md` and `config/network.conf.example`.

## Installation

```sh
sudo sh packaging/install.sh
```

## Validation

```sh
sha256sum -c checksums/SHA256SUMS
sh tests/smoke-test.sh
sh tests/network-dry-run.sh
```

An actual SSH server is required for end-to-end network integration tests. The packaged dry-run test validates parsing, version gates and command construction without contacting a host.

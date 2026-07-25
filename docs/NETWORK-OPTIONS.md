# Network architecture and options

## Transaction model

1. Create a unique remote staging directory under `.zstd-splitter.incoming`.
2. Acquire a per-archive lock with atomic `mkdir`.
3. Transfer each file as `.partial`, optionally resuming with SFTP.
4. Verify remote byte size and SHA-256 before renaming the part.
5. Upload the running script as a temporary remote verification helper.
6. Run strict manifest, part and reconstructed-archive checks remotely.
7. Optionally extract and validate the source inventory remotely.
8. Rename the complete staging directory to `ARCHIVE.bundle`.
9. Release the lock.

The remote helper is removed before publication. Payload files are never considered published while they carry the `.partial` suffix.

## Option groups

### Connection

- `identity=FILE`, `port=PORT`, `jump=HOST`
- `host-key-policy=strict|accept-new`, `known-hosts=FILE`
- `address-family=any|inet|inet6`
- `bind-interface=NAME`, `bind-address=ADDRESS`

### Reliability

- `resume=yes|no`, `atomic=yes|no`, `remote-fsync=yes|no`
- `retry=N`, `retry-delay=SECONDS`, `retry-backoff=linear|exponential`
- `connect-timeout=SECONDS`, `server-alive-interval=SECONDS`, `server-alive-count=N`
- `cleanup=success|always|never`, `lock=yes|no`

### Performance and network profiles

- `profile=safe|lan|jumbo-lan|wan|high-latency|metered|unstable|archive`
- `jobs=N`, `sftp-buffer=BYTES`, `sftp-requests=N`, `bandwidth=KBIT/S`
- `control-master=auto|yes|no`, `control-persist=SECONDS`
- `mtu-check=off|local|remote|path`, `mtu-required=BYTES`
- `tune=off|safe|adaptive`

`mtu-check=path` uses a non-fragmenting ping probe when the local platform supports it. It never changes the interface MTU. `stream-block` is an application buffer target and is independent of link MTU.

### 4.2 administration options

- repeated `-R` destinations
- `quorum=N`
- `audit-log=FILE`
- `gc-days=N`
- `-Q health`, `-Q inventory`, `-Q gc`
- `-Y` strict relay

## Limitations

Network file names containing newline characters are refused. The SFTP transport supports spaces and ordinary shell metacharacters through explicit quoting. Remote extraction requires the selected compression engine, `tar`, `sha256sum`, and the core utilities used by the script to be installed on the remote host.

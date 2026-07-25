# Testing

- `tests/smoke-test.sh` validates local compression, strict verification and extraction.
- `tests/network-dry-run.sh` validates option parsing, release gates and generated SSH commands without a server.
- `tests/mock-network-test.sh` uses local SSH/SFTP test doubles to exercise transactional push and pull.

The mock test does not validate cryptographic host authentication, real SFTP server behaviour, latency, packet loss or filesystem durability. A production qualification should use disposable SSH hosts and fault injection.

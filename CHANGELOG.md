# Changelog

## 3.0 — 2026-07-25

- Added optional strict SHA-256 integrity processing with `-i`.
- Added source-tree inventory and aggregate source digest.
- Added complete compressed-archive SHA-256 and byte-size validation.
- Added per-part SHA-256 and byte-size validation.
- Added sidecar manifests named `NAME.tar.EXT.manifest.sha256`.
- Added verification-only action `-v`.
- Added extraction action `-x` and destination option `-d`.
- Added direct reconstruction and extraction from any selected part.
- Added post-extraction source-tree validation.
- Added detection of source mutation during strict compression.
- Added explicit manifest selection with `-m`.
- Retained non-strict version 2.x workflows for backward compatibility.

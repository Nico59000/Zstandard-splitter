# Strict integrity manifest format

## Filename

For an archive named:

```text
NAME.tar.EXT
```

the default strict-integrity manifest is:

```text
NAME.tar.EXT.manifest.sha256
```

The same manifest travels beside all files named:

```text
NAME.tar.EXT.part.aaaaaa
NAME.tar.EXT.part.aaaaab
...
```

## Encoding

The format is UTF-8-compatible, line-oriented, and tab-separated. Structural
fields are ASCII. Path text is escaped before insertion:

| Input byte/character | Manifest representation |
|---|---|
| `%` | `%25` |
| horizontal tab | `%09` |
| carriage return | `%0D` |
| line feed | `%0A` |

This allows the inventory to retain unusual Unix pathnames without confusing
record boundaries.

## Header and metadata

The first line is:

```text
zstd-splitter-manifest<TAB>1
```

Required metadata records include:

```text
tool_version<TAB>3.0
engine<TAB>zstd
archive_name<TAB>NAME.tar.zst
archive_size<TAB>123456
archive_sha256<TAB>64-lowercase-hex-digits
source_root<TAB>NAME
source_entry_count<TAB>42
source_tree_sha256<TAB>64-lowercase-hex-digits
part_count<TAB>3
part_size_bytes<TAB>524288000
```

## Source records

Each source object is represented by one record:

```text
source<TAB>TYPE<TAB>SHA256-OR-DASH<TAB>SIZE<TAB>ESCAPED-RELATIVE-PATH
```

Types are:

- `F`: regular file; SHA-256 hashes the file content and size is its byte count.
- `D`: directory; digest is `-` and size is `0`.
- `L`: symbolic link; SHA-256 hashes the link-target text emitted by `readlink`,
  including its output newline, and size is the byte count of that emitted text.

Other filesystem object types are rejected in strict mode rather than silently
receiving incomplete semantics.

The `source_tree_sha256` value is the SHA-256 of the exact concatenation of all
`source` records, including tabs and terminating newlines. Traversal order is
stable under `LC_ALL=C` and is reproduced after extraction.

## Part records

Each split file is represented by:

```text
part<TAB>SUFFIX<TAB>SIZE<TAB>SHA256
```

Example:

```text
part<TAB>aaaaaa<TAB>524288000<TAB>64-lowercase-hex-digits
```

The suffix, rather than the complete pathname, is recorded so the part set and
manifest can be moved together without invalidating the inventory.

## Verification sequence

Strict reconstruction performs these checks in order:

1. Manifest header, required fields, counts, and digest syntax.
2. Internal source-record aggregate SHA-256.
3. Exact number of split parts.
4. Byte size and SHA-256 of every part.
5. Reconstruction in manifest order.
6. Byte size and SHA-256 of the complete compressed archive.
7. Native integrity test supplied by the selected compression engine.

Strict extraction then:

1. Extracts into a newly created dedicated directory.
2. Regenerates the source inventory from all extracted top-level objects.
3. Compares the aggregate source SHA-256.
4. Compares the complete source records byte for byte.

## Trust boundary

The manifest is a corruption-detection object, not a cryptographic signature.
An attacker able to replace both data and manifest can generate matching new
hashes. Authenticity requires an external signature or a trusted independently
stored manifest digest.

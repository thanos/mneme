# Phase 2 Persistence Concepts

## Canonical Data vs Derived Index Data

`mneme` persists canonical data (collection config + points). Search structures are derived state and rebuilt in memory after loading. This keeps on-disk state stable and independent from index implementation changes.

Persist canonical:

- collection name, dimension, metric
- point ids
- vectors
- metadata payloads

Do not persist derived:

- flat scan internals
- future HNSW graph
- future IVF clusters
- cached scores/distances

## Why Not Persist HNSW In Phase 2

Phase 2 is correctness-first. HNSW adds additional graph invariants and compatibility concerns. A canonical point format gives a clean base so future index versions can always rebuild from trusted records.

## Binary Format vs Text Format

Binary is chosen because vector payloads are numeric arrays and binary encoding is compact and fast to parse. Text would be larger, slower, and require parsing/formatting logic that adds noise to this phase.

## Versioning and Magic Bytes

- **Magic bytes** quickly reject unrelated files.
- **Version field** enables future format evolution with explicit compatibility checks.

If a file has unknown version, loader returns `UnsupportedVersion` rather than attempting unsafe decode.

## Endianness

Vectors and integer fields are encoded as little-endian values. Using fixed endianness avoids host-dependent ambiguity and keeps cross-platform decoding deterministic.

## Corruption Handling

Loader validates:

- header fields (magic/version/dimension/metric)
- record lengths
- vector length vs collection dimension
- full record availability (truncation)

Validation failures return explicit errors such as `InvalidMagic`, `TruncatedFile`, `CorruptRecord`, or `VectorLengthMismatch`.

Phase 2 also treats trailing bytes after the checksum footer as `CorruptRecord` to keep the parser strict.

## Integrity Checks

Phase 2 includes a `u32` CRC32 footer checksum computed over all bytes before the footer (header + all point records). Current corruption detection combines structural validation (magic/version/length/bounds checks) with checksum validation.

## Why Rebuild Search Structures

Flat search can operate directly on loaded points with no persisted index state. This confirms architecture layering: persistence stores truth data, and search behavior derives from it.

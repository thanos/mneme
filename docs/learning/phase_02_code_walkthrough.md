# Phase 2 Code Walkthrough

This walkthrough explains how canonical persistence was added while keeping search logic separate.

## `src/codec.zig`

Binary format details live here:

- writes header fields and point records in little-endian form
- validates magic, version, metric, and dimensions on read
- decodes owned point records for collection reconstruction

Key purpose: keep binary encoding/decoding out of search logic.

## `src/storage.zig`

File I/O orchestration:

- creates/opens collection files
- delegates byte-level work to `codec.zig`
- returns fully owned decoded collection data

Key purpose: isolate filesystem concerns from `Collection` behavior.

## `src/collection.zig`

Public persistence API:

- `saveToFile(path)` delegates to storage
- `loadFromFile(allocator, path)` rebuilds a collection from decoded canonical data

Search and point-management behavior from Phase 1 stays intact.

## Save Path

1. collection passes metadata + points to storage
2. storage writes header
3. storage writes each point record

Only canonical data is persisted.

## Load Path

1. storage decodes header and records with validation
2. collection is initialized from decoded metadata
3. decoded points are inserted into collection-owned memory
4. runtime search state is ready without persisted index internals

## Error Handling

Persistence introduces explicit format errors:

- `InvalidMagic`
- `UnsupportedVersion`
- `InvalidMetric`
- `TruncatedFile`
- `VectorLengthMismatch`

These complement existing dimension and IO errors.

## Tests

New tests verify:

- header and record codec round trips
- magic/version/vector-length/truncation failures
- save/load flows for empty, single-point, and many-point collections
- search correctness after load
- delete-then-save/load behavior

This confirms persisted points are canonical truth and search remains derived behavior.

# Architecture: `mneme` Phase 1 + 2 + 3 + 4

`mneme` Phase 1 is a single-process, in-memory vector database core with flat brute-force search.
It is intentionally single-threaded and correctness-first.

## Core Components

- `Collection`: owns points, config, and allocator.
- `Point`: id, owned vector data, optional metadata string.
- `Vector`: validation and math helpers (`dot`, `norm`).
- `Distance`: cosine similarity implementation.
- `FlatIndex`: scans all points and returns exact top-k ordered results.
- `HnswIndex`: in-memory approximate nearest-neighbor graph.
- `Storage`: file save/load orchestration for collections.
- `Codec`: binary format encode/decode.
- `C ABI`: stable exported layer (`src/c_api.zig`, `include/mneme.h`) over core Zig API.

## Data Flow

1. caller initializes `Collection` with allocator + dimension + metric.
2. caller inserts points; collection copies data into owned memory.
3. query calls `search`; collection validates dimension.
4. flat mode: `FlatIndex` computes cosine score for each point.
5. hnsw mode: `HnswIndex` traverses graph and returns approximate top-k.
6. results are sorted by score descending and top-k returned.

Persistence flow:

1. `Collection.saveToFile` delegates to `Storage`.
2. `Storage` uses `Codec` to write a versioned binary file.
3. `Collection.loadFromFile` decodes canonical points and rebuilds in-memory state.

ABI flow:

1. foreign runtime calls `mneme_*` C symbols.
2. C ABI validates pointers and maps types/errors.
3. C ABI delegates to `Collection`/search/storage APIs.
4. C ABI returns status codes + borrowed diagnostics (`mneme_last_error`).

## Validation Responsibilities

- `Collection` validates external API inputs (dimension checks, duplicate/missing ids).
- `Distance` and `Vector` helpers validate math preconditions (empty/mismatched/zero vectors).

## Mutation Semantics

- `Collection.delete` uses `swapRemove`, which is O(1) but does not preserve insertion order.
- Search result ordering is always recomputed from score, so point storage order is not part of the API contract.

## Phase 2 File Format (v2)

Header:

- magic bytes: `MNEME`
- format version: `u32`
- dimension: `u32`
- metric: `u8`
- collection name length: `u32`
- collection name bytes
- point count: `u64`

Point record:

- id length: `u32`
- id bytes
- metadata length: `u32` (`0xFFFFFFFF` represents null metadata)
- metadata bytes (if not null)
- vector length: `u32`
- vector values: `f32` little-endian

Footer:

- checksum: `u32` CRC32 over all prior file bytes (header + all point records)

Canonical persisted data:

- collection metadata
- point ids
- vectors
- metadata payloads

Derived and not persisted:

- flat index internals
- HNSW graph state (layers + links + entry point)
- cached scores/distances

## ASCII Diagram

```text
       +-----------------------------+     +------------------------+
       | Future wrappers             | --> | C ABI (`mneme_*`)      |
       | Python / Elixir / Rust/...  |     +-----------+------------+
       +-----------------------------+                 |
                                                       v
                +------------------------+    save/load +--------------------+
                |       Collection       | <----------> |      Storage       |
insert/search ->| canonical points[]     |             | file I/O + atomic  |
                | optional HnswIndex     |             | replace lifecycle  |
                +-----------+------------+             +---------+----------+
                            |                                    |
                    +-------+-------+                            v
                    |               |                   +--------------------+
                    v               v                   |       Codec        |
          +------------------+  +------------------+   | binary encode/decode|
          |    FlatIndex     |  |    HnswIndex     |   +--------------------+
          | exact top-k scan |  | approximate ANN  |
          +--------+---------+  +--------+---------+
                   \                    /
                    \                  /
                     v                v
                      +--------------------+
                      |   Distance.cosine  |
                      +---------+----------+
                                |
                                v
                      +--------------------+
                      |    SearchResult[]  |
                      +--------------------+
```

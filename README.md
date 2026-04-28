# mneme

`mneme` is an embedded-first vector / memory database core written in Zig.

The project currently implements **Phase 1 + Phase 2 + Phase 3 + Phase 4 (stable C ABI)**.

## Phase 1 Supports

- create a collection with fixed vector dimension and metric
- insert vectors with ids and optional metadata string
- delete vectors by id
- count vectors
- search nearest vectors with flat scan and cosine similarity

## Phase 2 Adds

- save collection canonical data to a versioned binary file (`.mneme`)
- load collection from file and rebuild in-memory search state

## Phase 3 Adds

- in-memory HNSW approximate nearest-neighbor search
- `searchWithOptions` to select flat or HNSW at query time
- `buildHnsw` to build derived ANN graph from canonical points

## Phase 4 Adds

- stable C ABI layer for collection lifecycle, search, HNSW, and persistence
- shared-library build target (`zig build lib`)
- installable C header (`include/mneme.h`)

## Not Supported Yet

- persisted ANN indexes (including persisted HNSW graph)
- metadata filtering
- network server mode
- Python/Elixir wrappers
- metadata filtering

## Build

```bash
zig build
```

## Build Shared Library (C ABI)

```bash
zig build lib
```

This builds a shared library (`libmneme.dylib` on macOS, `libmneme.so` on Linux) and installs `mneme.h`.

## Test

```bash
zig build test
```

## Lint

```bash
zig build lint
```

## Benchmark (Baseline)

```bash
zig build run
```

Runs:

- insert 10,000 vectors
- dimension 384
- search top 10
- save collection
- load collection
- flat search after load
- HNSW build
- HNSW search after build
- top-k overlap between flat and HNSW

The benchmark includes a soft regression warning if any stage exceeds 60 seconds.
The benchmark save path uses `saveToFileWithOptions(..., .{ .fsync_on_save = false })` to measure non-durable write throughput.

## Minimal Example

```zig
const std = @import("std");
const mneme = @import("mneme");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const vector = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &vector, "source=chat");

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try collection.search(&query, 10);
    defer collection.freeSearchResults(results);

    try collection.buildHnsw(.{
        .m = 16,
        .ef_construction = 128,
        .ef_search = 64,
        .seed = 42,
    });
    const ann_results = try collection.searchWithOptions(&query, 10, .{
        .index = .hnsw,
        .ef_search = 64,
    });
    defer collection.freeSearchResults(ann_results);

    try collection.saveToFile(".zig-cache/docs.mneme");
    var loaded = try mneme.Collection.loadFromFile(allocator, ".zig-cache/docs.mneme");
    defer loaded.deinit();
}
```

## C ABI

The C ABI exposes:

- collection create/load/free
- insert/delete/count
- batch insert/delete
- flat search and HNSW search
- HNSW build
- save/load
- result access + result free

Header:

- `include/mneme.h`
- practical integration guide: `docs/learning/phase_04_language_wrapper_guide.md`

Tiny C usage sketch:

```c
#include "mneme.h"

mneme_collection_t *c = NULL;
mneme_collection_create("docs", 3, MNEME_METRIC_COSINE, &c);
float v[3] = {1.0f, 0.0f, 0.0f};
mneme_collection_insert(c, "doc_1", v, 3, NULL);
mneme_results_t *r = NULL;
mneme_collection_search_flat(c, v, 3, 1, &r);
mneme_results_free(r);
mneme_collection_free(c);
```

Not supported yet in Phase 4:

- Python packaging/wrapper
- Elixir wrapper
- metadata filtering ABI
- HNSW persistence

## Notes


- The `.mneme` format is versioned. Unknown versions fail fast with `UnsupportedVersion`.
- Phase 2 canonical files persist collection metadata + points only; index state is derived and rebuilt.
- HNSW graph state is derived and in-memory only in Phase 3; it is not persisted.
- Phase 4 C ABI stores `mneme_last_error` in thread-local storage (per-thread error text).
- Current `.mneme` format (`format_version = 2`) rejects trailing bytes as `CorruptRecord` (strict parser).
- Phase 2 files include a CRC32 footer checksum over the encoded payload.
- Durable save mode (`fsync_on_save = true`) fsyncs both the data file and its parent directory after atomic rename.

## Format Compatibility Policy

- File format changes must increment `format_version`.
- New readers should keep support for prior stable format versions whenever practical.
- Unknown future versions fail safely with `UnsupportedVersion`.

## Persistence Errors

`loadFromFile` / `storage.loadCollection` may return:

- `InvalidMagic`
- `UnsupportedVersion`
- `InvalidMetric`
- `InvalidDimension`
- `TruncatedFile`
- `VectorLengthMismatch`
- `CorruptRecord`

## Roadmap

- Phase 2: persistence
- Phase 3: HNSW (implemented in-memory)
- Phase 4: C ABI (implemented)
- Phase 5: Python packaging or metadata filtering
- Phase 6: Elixir wrapper / server mode
- Later: HNSW persistence and SIMD acceleration

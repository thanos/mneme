# mneme

`mneme` is an embedded-first vector / memory database core written in Zig.

## What Is mneme

`mneme` is a local library, not a server. It focuses on:

- deterministic in-process behavior
- explicit memory ownership
- exact + approximate vector search
- a stable C ABI for language wrappers

Current state: Phase 1 through Phase 5 hardening are implemented (core engine + persistence + HNSW + C ABI + productization docs/CI).

## Why mneme Exists

Many vector systems optimize for distributed deployment first. `mneme` optimizes for:

- embedded use cases
- predictable host integration
- wrapper-friendly ABI contracts
- educational clarity of implementation

## Core Features

- fixed-dimension collections with cosine metric
- insert/delete/count
- exact flat top-k search
- in-memory HNSW ANN search
- canonical persistence (`.mneme`, current `format_version = 2`)
- stable C ABI (`include/mneme.h`)

## Zig Example

```zig
const std = @import("std");
const mneme = @import("mneme");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);

    var c = try mneme.Collection.init(gpa.allocator(), "docs", 3, .cosine);
    defer c.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try c.insert("doc_1", &v, null);

    const exact = try c.search(&v, 5);
    defer c.freeSearchResults(exact);

    try c.buildHnsw(.{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 42 });
    const ann = try c.searchWithOptions(&v, 5, .{ .index = .hnsw, .ef_search = null });
    defer c.freeSearchResults(ann);
}
```

## C Example

See runnable smoke example:

- `examples/c/basic.c`

Build and run:

```bash
zig build c-integration
```

## Persistence Format (`.mneme`)

- versioned binary format, current `format_version = 2`
- canonical data only (collection config + points)
- CRC32 footer checksum
- strict parser rejects trailing bytes
- HNSW graph is derived in-memory and rebuilt after load

## HNSW Support

- build index from current points: `buildHnsw`
- query-time selection via `searchWithOptions` (Zig) or `mneme_collection_search_hnsw` (C ABI)
- stale-index detection after mutations (`MNEME_ERROR_INDEX_STALE`)

## C ABI Usage

Header:

- `include/mneme.h`

Design + wrapper docs:

- `docs/design/c_abi.md`
- `docs/learning/phase_04_language_wrapper_guide.md`

Notes:

- `mneme_abi_version()` currently returns `1`
- `mneme_last_error()` is thread-local
- explicit ownership contract: creators/searchers allocate; callers free

## Build Instructions

```bash
zig build
zig build test
zig build lint
zig build lib
zig build c-integration
```

Coverage (Linux-oriented, `kcov` required):

```bash
zig build coverage
zig build coverage-c-integration
```

## Known Limitations

- no metadata filtering
- HNSW is not persisted
- no multi-query batch search optimization yet
- no Windows support workflow yet
- no Python/Elixir production wrapper packages yet

## Roadmap

- Phase 6: Python packaging over stable C ABI
- Phase 7: Elixir wrapper
- Later: metadata filtering + hybrid queries
- Later: persisted ANN structures and SIMD acceleration

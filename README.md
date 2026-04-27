# mneme

`mneme` is an embedded-first vector / memory database core written in Zig.

The project currently implements **Phase 1**: a minimal, correctness-first in-memory engine.

## Phase 1 Supports

- create a collection with fixed vector dimension and metric
- insert vectors with ids and optional metadata string
- delete vectors by id
- count vectors
- search nearest vectors with flat scan and cosine similarity

## Phase 2 Adds

- save collection canonical data to a versioned binary file (`.mneme`)
- load collection from file and rebuild in-memory search state

## Not Supported Yet

- persistence
- approximate indexes (HNSW/IVF)
- metadata filtering
- network server mode
- Python/Elixir/C bindings

## Build

```bash
zig build
```

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
- search after load

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

    try collection.saveToFile(".zig-cache/docs.mneme");
    var loaded = try mneme.Collection.loadFromFile(allocator, ".zig-cache/docs.mneme");
    defer loaded.deinit();
}
```

## Notes

- `prompts/` contains local planning artifacts and is not part of the runtime package API.

## Roadmap

- Phase 2: persistence
- Phase 3: HNSW
- Phase 4: C ABI
- Phase 5: Python packaging
- Phase 6: Elixir wrapper / server mode
- Phase 7: metadata filtering
- Phase 8: Apple Silicon acceleration

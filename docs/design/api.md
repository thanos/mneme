# API Design (Phase 1 + Phase 2 + Phase 3 + Phase 4)

## Public Types

- `Collection`
- `Metric` (`.cosine`)
- `SearchResult`
- `IndexKind` (`.flat`, `.hnsw`)
- `SearchOptions`
- `HnswConfig`
- `MnemeError`
- Phase 4 C ABI in `include/mneme.h` / `src/c_api.zig`

## Primary API

```zig
const std = @import("std");
const mneme = @import("mneme");
var gpa: std.heap.DebugAllocator(.{}) = .init;
defer std.debug.assert(gpa.deinit() == .ok);
const allocator = gpa.allocator();

var collection = try mneme.Collection.init(allocator, "docs", 384, .cosine);
defer collection.deinit();

try collection.insert("doc_1", vector, "source=chat");
try collection.delete("doc_1");
const n = collection.count();
const results = try collection.search(query_vector, 10);
defer collection.freeSearchResults(results);
try collection.buildHnsw(.{
    .m = 16,
    .ef_construction = 128,
    .ef_search = 64,
    .seed = 42,
});
const ann = try collection.searchWithOptions(query_vector, 10, .{
    .index = .hnsw,
    .ef_search = 64,
});
defer collection.freeSearchResults(ann);
try collection.saveToFile(".zig-cache/docs.mneme");
try collection.saveToFileWithOptions(".zig-cache/docs.mneme", .{ .fsync_on_save = false });
var loaded = try mneme.Collection.loadFromFile(allocator, ".zig-cache/docs.mneme");
defer loaded.deinit();
```

## Ownership Rules

- `Collection.init` duplicates `name`.
- `insert` duplicates `id`, vector contents, and optional metadata.
- `search` returns a freshly allocated slice where each result id is owned memory.
- caller must free results with `collection.freeSearchResults(results)`.
- `Collection.deinit` frees all owned memory.
- `buildHnsw` creates a derived in-memory ANN graph from current points.
- `searchWithOptions(..., .{ .index = .flat })` is equivalent to `search`.
- `searchWithOptions(..., .{ .index = .hnsw })` requires a built, non-stale HNSW index.
- `searchWithOptions(..., .{ .index = .hnsw, .ef_search = x })` coerces effective `ef` to `max(x, top_k)` so `ef` is never below requested result count.
- `searchWithOptions` takes mutable collection state (`*Collection`) because HNSW query path reuses internal scratch buffers.
- `insert`/`delete` invalidate HNSW by marking it stale; rebuild with `buildHnsw` before HNSW searches.
- HNSW stale lifecycle: insert/delete after a build cause `.hnsw` queries to return `IndexStale` until `buildHnsw` is called again.
- `loadFromFile` always starts with no HNSW graph (`IndexNotBuilt` for `.hnsw` searches until a build).
- `saveToFile` persists canonical data (collection metadata + points).
- `saveToFileWithOptions(path, options)` allows tuning durability/cost tradeoffs (for example disabling `fsync` for non-critical checkpoints or benchmarks).
- `loadFromFile` creates a collection from persisted canonical data and rebuilds runtime state.
- `storage.loadCollection(path, allocator)` returns `LoadedCollectionData`; callers must call `loaded.deinit()` using the same allocator captured in that object.

## Internal Types

`Collection` + `HnswConfig` are the intended user-facing HNSW surface.

Low-level graph internals (`HnswIndex`, `HnswNode`) are exposed under `mneme.internal.*` primarily for tests and low-level experimentation.

When using `mneme.internal.HnswIndex` directly, `build`, `insert`, and `search` must all operate on the same canonical `points` slice (node links store point indexes).

For observability, `mneme.internal.HnswIndex.stats(allocator)` returns lightweight graph diagnostics (node count, max level, layer histogram, average layer-0 degree).

## C ABI Surface (Phase 4)

The C ABI exposes a stable handle-based boundary:

- `mneme_collection_t` and `mneme_results_t` are opaque handles.
- all `mneme_*` functions return `mneme_status_t` (except scalar accessors/free/version).
- `mneme_last_error()` returns borrowed thread-local error text.

Core ABI calls:

- collection lifecycle: create/load/free
- mutation: insert/delete + batch insert/delete
- read path: count/search
- ANN path: build HNSW + search HNSW
- persistence: save/load
- results: len/id/score/free

### C ABI Ownership Rules

- `mneme_collection_create` / `mneme_collection_load` allocate collection handles.
- caller must call `mneme_collection_free`.
- search APIs allocate `mneme_results_t`.
- caller must call `mneme_results_free`.
- ids returned by `mneme_results_id` are borrowed and invalid after result free.
- `mneme_collection_insert_batch` and `mneme_collection_delete_batch` are fail-fast and provide optional processed-item counters.

### C ABI Notes

- collection search entrypoints accept mutable handles due to HNSW scratch reuse.
- C ABI delegates to public Zig API in `src/mneme.zig`; it does not expose `mneme.internal.*`.
- HNSW remains derived/in-memory only and is not persisted in `.mneme` files.
- for `mneme_collection_search_hnsw`, `ef_search = 0` means use default configured `ef_search`.

## Why Optional String Metadata

Phase 1 uses `?[]const u8` metadata for simplicity:

- fewer allocation paths than a map
- easier to teach ownership and deallocation
- enough to validate data model before filtering features

A key/value map can be introduced in a later phase when metadata filtering is implemented.
Metadata is stored during insert, but filtering/querying metadata is deferred to later phases.

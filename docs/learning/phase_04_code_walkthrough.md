# Phase 4 Code Walkthrough: Stable C ABI

## `include/mneme.h`

The header defines the public C boundary:

- opaque handle types (`mneme_collection_t`, `mneme_results_t`)
- status + metric constants
- HNSW config struct
- function list for lifecycle/search/persistence/result access

This is intentionally small to stay wrapper-friendly.

## `src/c_api.zig`

The ABI layer wraps existing Zig APIs from `src/mneme.zig` and does not expose internal graph structs.

Key pieces:

- exported C-callable functions (`export fn`)
- opaque handle casting helpers
- thread-local last-error buffer (`mneme_last_error`)
- Zig-error to status-code mapping
- input validation and null checking

## Opaque Handles

`mneme_collection_t` and `mneme_results_t` are opaque to C callers.
Internally they map to Zig structs that own:

- a `Collection`
- result items (NUL-terminated ids + scores)

## Collection Lifecycle

- `mneme_collection_create`: validates args, maps metric, allocates handle, initializes collection.
- `mneme_collection_free`: deinitializes collection and destroys handle.
- `mneme_collection_load`: loads persisted canonical collection into a new handle.

## Insert Path

`mneme_collection_insert`:

- validates collection/id/vector args
- converts C string + vector pointer/len into Zig slices
- delegates to `Collection.insert`
- maps errors like duplicate id and dimension issues to ABI status codes

`mneme_collection_insert_batch`:

- accepts id array + contiguous vector buffer to reduce FFI call overhead
- optionally accepts metadata pointer array
- fails fast on first invalid item/error
- reports successful prefix length via `out_inserted`

## Flat Search Path

`mneme_collection_search_flat`:

- validates pointers and dimensions
- delegates to `Collection.search`
- converts Zig search results into ABI result object with NUL-terminated ids

`mneme_results_len/id/score` expose index-based access without leaking internal layouts.

## HNSW Build/Search Path

- `mneme_collection_build_hnsw` maps C config to `HnswConfig` and builds graph.
- `mneme_collection_search_hnsw` calls `searchWithOptions(.hnsw)`.
- in C ABI, `ef_search = 0` means "use default index ef_search"; non-zero values act as per-call overrides.
- stale/not-built states map to `INDEX_STALE`/`INDEX_NOT_BUILT`.

## Save/Load Path

- `mneme_collection_save` delegates to `Collection.saveToFile` (durable save path).
- `mneme_collection_load` creates a collection from `.mneme` canonical data.
- HNSW remains derived and must be rebuilt after load when needed.

## Result Ownership

Search allocates an opaque result object.

- ids returned by `mneme_results_id` are borrowed from result object
- caller must call `mneme_results_free`
- pointers returned by `mneme_results_id` are invalid after free

## Last-Error Handling

`mneme_last_error` returns a thread-local message buffer.

- caller never frees it
- error text is isolated per thread

## Status Mapping

The ABI maps expected engine/storage errors into stable `mneme_status_t` values and reserves `MNEME_ERROR_INTERNAL` for unexpected failures.

## Locking and Thread-Safety

- each `mneme_collection_t` handle has an internal lock in the ABI layer.
- calls touching the same collection handle are serialized by this lock.
- this makes same-handle access thread-safe, but does not parallelize operations on that same handle.
- `mneme_collection_free` must not race with other calls on the same handle.
- `mneme_last_error` remains thread-local and independent per thread.

## Tests

`test/c_api_test.zig` covers:

- versioning
- lifecycle
- null/invalid argument checks
- insert/delete/count/search
- HNSW state behaviors
- save/load through ABI
- error text population

## Build Changes

`build.zig` now includes:

- shared library build step (`zig build lib`)
- header installation
- C ABI test registration in `zig build test`

Phase 4 keeps the Zig-native API intact and adds a stable native boundary for future wrappers.

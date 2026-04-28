# C ABI Design (Phase 4)

## Goals

- Expose stable C-callable surface for `mneme` core features.
- Keep ABI small, handle-based, and wrapper-friendly.
- Preserve existing Zig API and internal architecture.

## ABI Versioning

- `mneme_abi_version()` returns ABI version (`1` in Phase 4).
- Future breaking ABI changes must increment this version.

## Status Codes

- `MNEME_OK`
- `MNEME_ERROR_INVALID_ARGUMENT`
- `MNEME_ERROR_OUT_OF_MEMORY`
- `MNEME_ERROR_DIMENSION_MISMATCH`
- `MNEME_ERROR_IO`
- `MNEME_ERROR_INDEX_NOT_BUILT`
- `MNEME_ERROR_INDEX_STALE`
- `MNEME_ERROR_INTERNAL`

## Type Definitions

- `mneme_collection_t` (opaque handle)
- `mneme_results_t` (opaque handle)
- `mneme_metric_t` (`MNEME_METRIC_COSINE`)
- `mneme_hnsw_config_t` (`m`, `ef_construction`, `ef_search`, `seed`)

## Function List

- `mneme_abi_version`
- `mneme_last_error`
- `mneme_collection_create`
- `mneme_collection_free`
- `mneme_collection_insert`
- `mneme_collection_insert_batch`
- `mneme_collection_delete`
- `mneme_collection_delete_batch`
- `mneme_collection_count`
- `mneme_collection_search_flat`
- `mneme_collection_build_hnsw`
- `mneme_collection_search_hnsw`
- `mneme_collection_save`
- `mneme_collection_load`
- `mneme_results_len`
- `mneme_results_id`
- `mneme_results_score`
- `mneme_results_free`

HNSW search ABI convention:

- `mneme_collection_search_hnsw(..., ef_search, ...)` treats `ef_search = 0` as "use default configured ef_search".
- non-zero `ef_search` overrides default behavior for that call.
- use `MNEME_EF_SEARCH_DEFAULT` for readability instead of raw `0`.

## Ownership Rules

- create/load allocate collection handles; caller frees via `mneme_collection_free`.
- search allocates result handles; caller frees via `mneme_results_free`.
- ids returned by `mneme_results_id` are borrowed and tied to result lifetime.
- `mneme_last_error` string is borrowed static storage and must not be freed.
- batch operations are fail-fast and non-transactional.
- `out_inserted` / `out_deleted` report successfully processed items before first failure.

## Thread-Safety Notes

- `mneme_last_error` uses thread-local storage; each thread has its own independent error buffer.
- operations on the same collection handle are serialized by an internal per-collection mutex in the C ABI layer.
- same-handle access is thread-safe but not parallelized (single critical section per handle).
- `mneme_collection_free` is not safe to call concurrently with other operations on the same handle; callers must serialize free against in-flight calls.
- `mneme_collection_save` currently holds the per-collection lock for the duration of the save path, including file I/O and fsync operations.

## Known Limitations

- only cosine metric supported.
- metadata remains simple optional string payload.
- HNSW graph is not persisted.
- no metadata filtering ABI yet.
- no Windows packaging workflow yet.

## Wrapper Guidance

Practical wrapper examples and usage patterns are documented in:

- `docs/learning/phase_04_language_wrapper_guide.md`

### Python

- Use `ctypes` or `cffi`.
- Wrap opaque pointers in Python classes with deterministic `close()` and fallback finalizers.
- Convert result iteration into Python lists/dicts while preserving ownership rules.

### Elixir

- Use a Port or NIF wrapper.
- Keep resource ownership explicit and always pair `create/load/search` with free calls.
- Surface status + last-error text as idiomatic `{:ok, ...}` / `{:error, reason}` tuples.

### Rust / Swift

- Rust: `extern "C"` + safe wrapper types for RAII drops.
- Swift: import C header through module map/bridging header and wrap handles in classes/structs with `deinit`.
- In both, convert borrowed result-id pointers immediately if data outlives result handle.

## Coexistence with Zig API

The Zig-native API remains the primary in-repo interface and test target.
The C ABI is a boundary layer that delegates to the same engine logic; wrapper runtimes should not call internal Zig symbols directly.

## ABI Evolution Policy

- Additive changes (new exported functions/constants) may ship without bumping `mneme_abi_version`.
- Any change to existing function signatures, status-code values, or ownership contracts must bump `mneme_abi_version`.
- Removed exports require a version bump and should be documented with migration notes in this file.
- Wrappers should check `mneme_abi_version()` at load time and fail fast on unsupported versions.

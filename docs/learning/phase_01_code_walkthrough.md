# Phase 1 Code Walkthrough

This walkthrough reflects the implemented code for the in-memory flat-search baseline.

## `src/errors.zig`

Defines `MnemeError` for API-level failures:

- invalid/empty vectors
- zero vectors for cosine
- duplicate/missing ids

## `src/vector.zig`

Contains low-level vector helpers:

- `ensureDimension` for collection/query safety checks
- `dot` and `norm` for similarity math
- `isZeroVector` helper used by tests and safety checks

## `src/distance.zig`

Implements `cosineSimilarity(a, b)`:

- validates through vector helpers
- computes `dot / (norm_a * norm_b)`
- rejects zero-vector normalization via `MnemeError.ZeroVector`

## `src/point.zig`

`Point.init` duplicates id/vector/metadata into collection-owned memory.  
`Point.deinit` frees each owned allocation.

## `src/index.zig`

`FlatIndex.search`:

1. scans every point
2. computes cosine score
3. sorts by descending score
4. returns allocated top-k slice

This is brute-force by design to maximize correctness and clarity.
Result ids are duplicated so search results remain valid even if the collection mutates afterward.

## `src/collection.zig`

`Collection` is the main API surface:

- `init`: sets config and ownership roots
- `insert`: validates vector dimension, rejects duplicate id
- `delete`: removes by id and frees point memory
- `count`: returns point count
- `search`: validates query dimension and delegates to flat index
- `freeSearchResults`: frees result ids and the result slice

## `src/main.zig`

Provides a baseline benchmark mode:

- inserts 10,000 vectors (dimension 384)
- executes top-10 search
- prints elapsed milliseconds

## Test Coverage

- `test/vector_test.zig`: dimension and zero-vector behavior
- `test/distance_test.zig`: cosine correctness and edge-case errors
- `test/collection_test.zig`: API behavior and ordered top-k results
- `test/index_test.zig`: flat scan and top-k bounds behavior

Together these tests establish a correctness baseline for future persistence and ANN phases.

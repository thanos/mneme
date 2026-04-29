# Phase 3 Walkthrough: In-Memory HNSW in `mneme`

## HnswConfig

`HnswConfig` controls graph degree and search breadth:

- `m`: maximum neighbors retained per node per layer
- `ef_construction`: candidate breadth during build/insert
- `ef_search`: default candidate breadth during query
- `seed`: deterministic random seed for level assignment

Validation requires:

- `m > 0`
- `ef_construction >= m`
- `ef_search > 0`

## HnswNode and HnswIndex

Each `HnswNode` stores:

- `point_index` (index into canonical `Collection.points`)
- `level` (highest layer for this node)
- `neighbors_by_layer` (neighbor node indexes per layer)

`HnswIndex` owns:

- graph nodes
- entry point
- max level
- seeded PRNG
- cached point norms (`point_norms`)
- epoch-based visited marks (`visit_marks`, `visit_epoch`)
- reusable scratch buffers for build-time searches/pruning

Vectors are not duplicated into HNSW; canonical vectors stay owned by `Collection`.

## Random Level Assignment

`randomLevel()` uses seeded random draws and a geometric-style threshold (`p = 0.5`) to generate exponentially decaying levels:

- many level 0 nodes
- fewer higher-level nodes

With the same seed and insertion order, level assignment is deterministic for tests.
Levels are capped at `32` to keep layer allocations bounded.

## Build Flow

`build(points)`:

1. clears prior graph state
2. inserts each point index in deterministic order
3. initializes/updates entry point and max level as needed

## Insert Flow

`insert(points, point_index, vector)`:

1. assign random level
2. create node with per-layer neighbor lists
3. if first node, set entry point and stop
4. greedily descend upper layers from entry point
5. run candidate search on each relevant layer
6. connect bidirectionally to selected neighbors
7. batch-prune affected neighbor lists back to `m`

During this process, build uses reusable scratch candidate/result/touched buffers plus epoch-based visited tracking to reduce allocator overhead without changing behavior.

## Search Flow

`search(points, query, top_k, ef_override)`:

1. validate query dimension
2. greedy descent from top layer to layer 0
3. candidate expansion on layer 0 with `ef_search`
4. sort by cosine score descending
5. return top-k `SearchResult` values

If `ef_override` is provided, implementation uses `max(ef_override, top_k)` so callers cannot accidentally request `ef < top_k`.
This search path uses mutable internal scratch/visited state for efficiency, so it is modeled as mutable (`*HnswIndex`) in Phase 3.

## Neighbor Pruning

When neighbor count exceeds `m`, neighbors are rescored by cosine similarity against the node's vector and pruned to top `m`.

This is a simplified HNSW policy chosen for readability and deterministic behavior.

## Collection Integration

`Collection` now supports:

- `buildHnsw(config)`
- `searchWithOptions(query, top_k, options)`

Behavior:

- `search` remains flat by default for backward compatibility
- `searchWithOptions(.flat)` uses flat index
- `searchWithOptions(.hnsw)` requires HNSW built and not stale
- `insert` and `delete` mark HNSW stale
- `loadFromFile` does not load HNSW (must rebuild explicitly)

## Test Strategy

Phase 3 adds:

- `test/hnsw_test.zig`: construction/search/config invariants
- `test/hnsw_recall_test.zig`: HNSW vs flat overlap/recall checks
- `test/hnsw_collection_test.zig`: collection-level integration and stale-state behavior

All tests are deterministic via explicit seeds and deterministic datasets.

## Benchmark Strategy

Benchmark now reports:

- insert
- save
- load
- flat search
- HNSW build
- HNSW search
- overlap between flat and HNSW top-k

This provides an educational baseline for latency/recall tradeoff analysis.

## Known Simplifications

- cosine-only metric path
- simple sort/prune candidate management
- no incremental delete support in graph internals
- no persisted HNSW graph format
- no SIMD/heap-optimized candidate queues
- `ef_search` overrides are coerced upward to at least `top_k`

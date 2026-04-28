# Phase 3 Learning: Zig Graph Structures for HNSW

## Graph Modeling Approach

In Phase 3, HNSW is modeled as:

- `ArrayList(HnswNode)` for nodes
- each node owns per-layer neighbor lists
- neighbor links store node indexes (not copied vectors)

This keeps memory ownership clear and avoids duplicating canonical point data.

## Node Representation

Each node conceptually needs:

- `point_index`: index into `Collection.points`
- `level`: highest layer for this node
- `neighbors_by_layer`: neighbor node ids per layer

The graph references points indirectly, so canonical vectors remain owned by `Collection`.

## Ownership and Deinit Patterns

Nested `ArrayList` values require explicit teardown:

1. deinit each layer neighbor list
2. free container holding per-layer lists
3. deinit top-level node array

This pattern is critical to avoid leaks in graph-heavy structures.

## Candidate Sets and Sorting

For Phase 3 clarity, candidate management uses simple dynamic arrays:

- append scored candidates
- sort by score where needed
- prune to configured limits (`m` or `ef`)

This is easier to audit than heap-heavy optimizations and sufficient for correctness-focused learning.

The optimized Phase 3 implementation also reuses scratch buffers instead of allocating fresh candidate lists in each inner loop:

- `scratch_candidates`
- `scratch_results`
- `scratch_touched`

This keeps code readable while reducing allocator churn.

## Deterministic Random Levels

Use a seeded PRNG in Zig so tests are repeatable:

- fixed seed => stable level assignments and graph shape
- test assertions stay deterministic

The level generator should create exponentially decaying levels (many low-level nodes, few high-level nodes).

Current implementation details:

- threshold probability `p = 0.5`
- hard cap `level <= 32` to keep per-node layer storage bounded

These constants are simple and deterministic for educational use.

## Efficient Visited Tracking

Instead of allocating/clearing a `[]bool` visited array every layer search during build, `HnswIndex` uses:

- `visit_marks: ArrayList(u32)`
- `visit_epoch: u32`

Each search increments the epoch and marks visited nodes with that epoch value. This avoids repeated full clears and keeps deterministic behavior.

## Point Indexes vs Data Duplication

Store indexes in the graph:

- lower memory overhead
- no ownership ambiguity for vectors
- easy rebuild from canonical points

Tradeoff:

- search needs `points` slice to compute scores by node->point lookup

That tradeoff is acceptable and explicit in Phase 3.

# Phase 3 Learning: HNSW Concepts

## Why This Phase Exists

Flat search is exact: it scores every point for every query. That is easy to reason about and is a strong correctness baseline, but query cost grows linearly with collection size.

HNSW (Hierarchical Navigable Small World) is an approximate nearest-neighbor (ANN) method that trades some recall for lower latency.

## Exact vs Approximate Search

- Exact (FlatIndex): checks all points, highest recall, predictable, slower at scale.
- Approximate (HNSW): checks a subset guided by graph structure, much faster, may miss some exact neighbors.

## Small-World Graph Intuition

HNSW builds a layered proximity graph:

- lower layer (layer 0): dense local neighborhood links
- higher layers: progressively sparser long-range links

Search starts from the top entry point and greedily moves toward better candidates, then performs broader candidate expansion on layer 0.

## Key Terms

- **entry point**: node where search starts
- **max level**: highest layer present in the graph
- **M**: max neighbors retained per node per layer
- **ef_construction**: candidate breadth used while inserting/building
- **ef_search**: candidate breadth used during query
- **recall**: overlap with exact nearest neighbors
- **latency**: query runtime

## Why Random Levels

Each node gets a random maximum level using an exponentially decaying distribution:

- many nodes at level 0
- fewer at level 1
- very few at higher levels

This creates a navigable hierarchy: coarse routing above, fine routing below.

Implementation constants in this phase:

- probability threshold `p = 0.5` for level promotion
- hard cap `level <= 32`

These choices keep the implementation simple, deterministic, and bounded for educational purposes.

## Similarity Semantics in `mneme`

Public search scores remain cosine similarity:

- higher score = more similar

Any internal distance transformation is implementation detail; result ordering still follows descending cosine score.

## Why HNSW Is Not Persisted in Phase 3

Phase 2 already defines canonical persisted data:

- collection metadata
- point ids
- vectors
- metadata payloads

HNSW is derived runtime state and can be rebuilt from canonical points. Keeping it out of `.mneme` preserves format simplicity and compatibility while Phase 3 focuses on algorithm correctness and API design.

If you use low-level HNSW internals directly, remember that graph nodes store indexes into the canonical points array. Build/insert/search must reference the same points slice.

## Worked 2D Example (Conceptual)

Assume points:

- A: (1.0, 0.0)
- B: (0.9, 0.1)
- C: (0.0, 1.0)
- D: (0.1, 0.9)

Query Q: (1.0, 0.0)

Flat search scores all 4 points and sorts exactly.

HNSW path:

1. start at entry point in highest layer
2. greedily move to better neighbors (closer to Q)
3. descend layers
4. at layer 0, explore an `ef_search` candidate set
5. return top-k by cosine score

If graph links are good, HNSW quickly reaches A/B without scanning every point.

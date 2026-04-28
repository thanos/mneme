# Future Phases

## Phase 2: Persistence (implemented)

- Added canonical binary persistence for collection metadata and points.
- Added load/save lifecycle with versioned file header validation.
- Kept index state derived (rebuild from loaded points).

## Phase 3: HNSW (implemented in-memory)

- Add approximate nearest-neighbor index with recall/latency tradeoffs.
- Rebuild HNSW from canonical persisted points.
- Keep flat index as correctness oracle.

## Phase 4: C ABI (implemented)

- Expose stable C ABI through opaque handles and status codes.
- Add shared library build target and C header installation.
- Keep Zig-native API as first-class interface.

## Phase 5: Python Packaging or Metadata Filtering

- Provide Python bindings/package workflow, or prioritize metadata filtering depending on product direction.

## Phase 6: Elixir Wrapper / Server Mode

- Add Elixir wrapper and optional server process for network access.

## Later: HNSW Persistence

- Persist HNSW graph state (node levels, neighbor links, entry point, and config) with explicit format-version strategy.

## Later: SIMD / Apple Silicon Acceleration

- Evaluate SIMD/Accelerate optimizations for dot products and norms.

## Current Benchmark Baseline

Command:

`zig build run`

Scenario:

- insert 10,000 vectors
- dimension 384
- save and load canonical collection
- flat search top 10
- HNSW build
- HNSW search top 10
- flat/HNSW top-k overlap estimate

Record your local elapsed time from command output to track regressions and later speedups.

# Phase 1 Vector Database Concepts

## Embeddings And Vectors

An embedding is a numeric representation of data (text, image, etc.) produced by an ML model. `mneme` stores vectors; it does not generate embeddings. This separation is important because model choice and storage/query concerns evolve independently.

## Why Dimension Matters

A collection has a fixed dimension (for example, 384). Every inserted vector and query vector must match this dimension so distance math remains valid and predictable.

## Cosine Similarity

Phase 1 uses cosine similarity:

`cosine(a, b) = dot(a, b) / (norm(a) * norm(b))`

Interpretation:

- 1.0 means vectors point in the same direction
- 0.0 means orthogonal vectors
- negative values indicate opposite direction

## Query-Time Distance Computation

Distances are computed at search time by scanning points and scoring each one. This is expensive for large datasets but very clear and correct, which makes it the right baseline before adding approximate indexes.

## Why Flat Scan First

Flat scan is:

- easy to reason about
- easy to test
- great as a correctness baseline

Future ANN indexes (like HNSW) should match its behavior within known approximation bounds.

## Why HNSW Comes Later

HNSW improves query speed but adds graph construction complexity, tuning parameters, and trickier edge cases. Building flat search first reduces risk and gives a trusted reference implementation.

## Metadata Filtering Is Separate

Vector similarity and metadata filtering solve different problems. In Phase 1 metadata is stored only; filtering logic comes later so core vector operations remain focused and testable.

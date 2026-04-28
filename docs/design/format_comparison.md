# Persistence Format Comparison

This note compares `mneme` Phase 2 persistence with common vector database systems.

## `mneme` (Phase 2)

- Explicit, documented binary format (`.mneme`) with magic + version.
- Persists canonical records only:
  - collection metadata
  - point ids
  - vectors
  - metadata payloads
- Keeps index state derived and rebuildable.

This favors transparency, testability, and educational clarity.

## `pgvector`

- Integrates with PostgreSQL storage and wire protocols.
- Binary representation of vectors is stable in PostgreSQL ecosystem, but persistence is still tied to Postgres page/layout internals and extension behavior.
- Great for SQL-centric workloads and transactional semantics.

## Milvus

- Distributed system with segment-oriented internal persistence.
- Persists raw field data, metadata, and index artifacts across internal services/storage layers.
- Not a small user-facing single-file format contract.

## Chroma

- Embedded/application-focused, with internal persistence artifacts (metadata stores + embedding mappings + ANN artifacts).
- Persistence layout is engine-internal and implementation-driven.

## Why `mneme` chose explicit canonical format first

- Easier to reason about during early phases.
- Decouples on-disk truth from ANN index implementation details.
- Allows Phase 3+ index evolution (HNSW/IVF changes) without data migration of canonical records.

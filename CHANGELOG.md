# Changelog

All notable project changes are documented here by milestone phase.

## v0.5.0 — Phase 5: Productization & ABI Hardening

- harden ABI invalid-argument output-pointer clearing behavior
- strengthen ownership/threading contracts in headers and design docs
- add runnable language wrapper examples (`examples/python`, `examples/rust`)
- add `VERSIONING.md`, `CHANGELOG.md`, and `CONTRIBUTING.md`
- improve CI/build/docs for distributable external consumption

## v0.4.0 — Phase 4: Stable C ABI

- introduce stable C ABI (`src/c_api.zig`, `include/mneme.h`)
- add C smoke integration (`examples/c/basic.c`)
- add ABI tests and error/status mapping
- add shared library build/install support

## v0.3.0 — Phase 3: HNSW

- add in-memory HNSW index
- add `searchWithOptions` for flat/HNSW selection
- add HNSW tests and recall/perf evaluation coverage

## v0.2.0 — Phase 2: Persistence

- add `.mneme` save/load pipeline with versioned codec
- add atomic replace + durability options + checksum

## v0.1.0 — Phase 1: Core Engine

- initial in-memory vector collection model
- insert/delete/count + exact flat cosine search

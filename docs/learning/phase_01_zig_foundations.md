# Phase 1 Zig Foundations (Using `mneme`)

## Why Zig For Embedded Database Engines

Zig gives low-level control over memory and data layout while still providing a modern toolchain and built-in testing. For an embedded vector engine, this is useful because:

- allocator usage is explicit
- ownership is visible in function signatures
- no hidden runtime or GC pauses
- C interoperability is straightforward for future wrappers

## Core Zig Concepts Used In This Project

## Allocator

`Collection.init(allocator, ...)` requires an allocator up front. Any data that outlives a stack frame is allocated through this allocator, and cleaned in `deinit()`.

## Slices And Arrays

- `[]const f32` is a read-only slice used as API input.
- owned vectors are copied into allocated `[]f32` buffers when inserting points.

## Structs And Enums

- `Collection`, `Point`, and `SearchResult` are structs.
- `Metric` is an enum; Phase 1 supports `.cosine`.

## Error Unions

Functions return `!T` to model recoverable failures:

- invalid dimensions
- duplicates/missing ids
- empty or zero vectors for cosine

## Optionals

Metadata uses `?[]const u8`. `null` means "no metadata". This keeps the model simple while still teaching optional handling.

## Ownership Conventions

- `insert()` duplicates id/vector/metadata into collection-owned memory.
- caller owns temporary input buffers.
- `search()` returns an allocated slice with owned result ids; caller must use `collection.freeSearchResults(...)`.

## `defer`

`defer` is used heavily to ensure cleanup:

- deinit the collection
- free temporary allocations
- free benchmark and test buffers

## Testing In Zig

Zig tests are regular functions using `test "name" { ... }`. Assertions use `std.testing.expect*` helpers and can verify both success values and expected errors.

## Build System Basics

`build.zig` defines:

- module import (`mneme`)
- executable target (`src/main.zig`)
- test steps for root and integration-style test files

This keeps usage simple:

- `zig build run` for benchmark mode
- `zig build test` for all tests

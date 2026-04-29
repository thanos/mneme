# Phase 5 Learning: Productization

Phase 5 is where a good engine becomes a usable product surface.

## What Makes a Good Native Library

- predictable behavior on bad inputs
- explicit memory ownership
- stable compatibility boundaries
- reproducible build and test workflow
- runnable examples that match shipped artifacts

## ABI vs API Stability

- API stability is source-level (for Zig callers in this repo)
- ABI stability is binary-level (for C/Python/Rust/Elixir wrappers)

ABI mistakes are expensive because wrappers often compile once and run across many environments.

## Why Memory Contracts Matter

FFI bugs are usually ownership bugs:

- who allocates?
- who frees?
- how long is a borrowed pointer valid?

If docs and code disagree, wrappers become brittle.

## Why Examples Matter More Than Explanations

A runnable example validates:

- symbol names
- argument contracts
- linking and runtime loader behavior
- real ownership flow

If example code breaks, wrapper users will break too.

## Why CI Is Part of Architecture

CI is not just process hygiene. It encodes cross-platform assumptions:

- Linux + macOS build behavior
- C smoke integration
- repeatability of ABI expectations

If CI doesn’t exercise the product boundary, the boundary is not truly stable.

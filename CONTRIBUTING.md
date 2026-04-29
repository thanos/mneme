# Contributing

Thanks for contributing to `mneme`.

## Build

```bash
zig build
zig build lib
```

## Test and Lint

```bash
zig build test
zig build lint
```

Optional coverage (Linux + `kcov`):

```bash
zig build coverage
zig build coverage-c-integration
```

## Coding Style

- keep changes small and focused
- preserve explicit ownership and cleanup paths
- avoid implicit behavior at ABI boundaries
- add tests for behavior changes, especially failure paths
- keep docs in sync with implementation contracts

## Phase-Based Development Philosophy

`mneme` is developed in deliberate phases:

- each phase has a constrained scope
- avoid adding out-of-phase features
- prioritize correctness + documentation + testability
- ship stable contracts before wrapper packaging

When in doubt, favor clarity and explicit invariants over cleverness.

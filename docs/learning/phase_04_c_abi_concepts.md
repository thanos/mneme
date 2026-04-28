# Phase 4 Learning: C ABI Concepts

## What is an ABI?

An ABI (Application Binary Interface) defines how compiled code talks to other compiled code at runtime:

- function calling convention
- symbol names
- type layouts
- memory ownership expectations

An API describes source-level usage; an ABI describes binary-level compatibility.

## Why C ABI?

C ABI is the most portable bridge across runtimes. Languages like Python, Elixir, Rust, Swift, and many server/plugin systems can call C-compatible symbols directly.

## Opaque Handles

Expose pointers to incomplete types in headers:

- callers can pass handles around
- callers cannot mutate internal Zig structs directly
- internals can evolve while ABI remains stable

This phase uses:

- `mneme_collection_t`
- `mneme_results_t`

## Ownership Across Boundaries

Cross-language memory rules must be explicit.

- Create/load allocate collection handles.
- Search allocates result handles.
- Caller frees collections/results with matching ABI free functions.
- `mneme_results_id()` returns borrowed pointers owned by the result object.

Borrowed pointers become invalid after `mneme_results_free()`.

## Why Status Codes

Many languages cannot safely consume Zig errors directly. ABI functions return a compact status code (`mneme_status_t`) and expose diagnostic text via `mneme_last_error()`.

## Why Panics Must Not Cross ABI

Unwinding/panic behavior is runtime-specific and unsafe across foreign boundaries. ABI calls must catch/translate failures into stable status values.

## Strings and Arrays

- C strings: NUL-terminated `const char*`.
- vectors: pointer + length (`const float*` + `uint32_t`).
- results: opaque object + index-based accessors.

This avoids exposing unstable internal layouts in public headers.

## Why This Unlocks Wrappers

Once the C ABI is stable, wrapper layers become thinner:

- Python: `ctypes`/`cffi`
- Elixir: Port/NIF boundary
- Rust: `extern "C"` FFI
- Swift: C module import

Each wrapper can focus on ergonomic language-level APIs while delegating storage/search logic to the same native core.

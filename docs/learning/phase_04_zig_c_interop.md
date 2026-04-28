# Phase 4 Learning: Zig C Interop

## `export fn`

Zig exports C-callable symbols with `export fn`:

- symbol is visible in shared library
- C-compatible calling convention is used
- function signature should use C-safe types

## C-Compatible Types

Prefer fixed-width integer and pointer forms:

- `u32`, `u64`, `f32`
- `?[*:0]const u8` for nullable C strings
- `?[*]const f32` + explicit length for arrays
- opaque pointer handles for stateful objects

## Sentinel-Terminated Strings

C strings are NUL-terminated. In Zig:

- convert with `std.mem.span(c_str)`
- allocate C-facing ids with sentinel (e.g. `dupeZ`) when returning `const char*`

## Pointer Validation

Every exported function validates:

- required input pointer non-null
- out-pointer non-null before write
- pointer/length combinations are coherent

## Converting C Inputs to Zig Slices

- string inputs: `std.mem.span(name_ptr)`
- vector inputs: pointer + length converted to `[]const f32`

Zero-length slices may be represented with empty slices; nonzero lengths require non-null pointers.

## Allocator Choice

The ABI layer uses a stable allocator policy and keeps ownership pairings explicit:

- collection handle lifecycle
- results object lifecycle
- per-result id storage lifecycle

## Error Mapping

Zig errors are caught and mapped to `mneme_status_t`, with human-readable diagnostics available through `mneme_last_error()`.

## Shared Library Build

`build.zig` adds a shared library target so `zig build lib` produces:

- `libmneme.dylib` on macOS
- `libmneme.so` on Linux

The C header is installed alongside the library artifact.

## Header Files

`include/mneme.h` is the source of truth for foreign consumers:

- status constants
- metric constants
- opaque handle declarations
- ABI function signatures

## Testing Exported Functions from Zig

Zig tests can directly call exported ABI functions from `src/c_api.zig`:

- validates C boundary semantics
- validates error/status mapping
- validates ownership/free behavior

This gives fast coverage before adding language-specific wrappers.

# Phase 2 Zig File I/O

## Opening Files

Phase 2 uses POSIX-style open calls via Zig:

- `std.posix.openat(..., .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, ...)` for temp file creation on save
- `std.posix.openat(..., .{ .ACCMODE = .RDONLY }, ...)` for load
- `std.c.close(fd)` under `defer` so descriptors are always released

## Reading and Writing

Structured binary I/O is implemented in `codec.zig` using writer/reader operations:

- write fixed-width integers in little-endian form
- write counted byte slices
- write/read vector payloads in bulk byte slices for performance

On read, every counted field is bounded and validated before allocation.

## Buffered vs Unbuffered I/O

Phase 2 favors straightforward unbuffered descriptor I/O for explicit control over format checks and error propagation.

## Allocators During Load

Loading allocates owned memory for:

- collection name
- point ids
- optional metadata payloads
- vectors

If decode fails mid-stream, `errdefer` cleanup is used to prevent leaks.

## Ownership After Load

Loaded records are transferred into collection-owned memory without re-allocating vectors/ids. Callers only manage:

- collection lifecycle via `deinit`
- search result lifecycle via `freeSearchResults`

## `defer` and `errdefer` Patterns

- `defer`: always close files and release long-lived resources.
- `errdefer`: rollback partial allocations when a function exits with error.

This is especially important in decode paths where multiple allocations occur per record.

## Save Durability Model

- Save writes to `path + ".tmp"` first.
- On success, `fsync` is called on the temp file descriptor.
- The temp file is renamed over the destination path.

This atomic replace pattern avoids truncating an existing good file during mid-write failures.

## Testing with Temporary Files

Storage tests currently write under `.zig-cache/` and delete files with `defer` cleanup helpers. Corruption scenarios are tested by writing malformed/truncated bytes and asserting explicit decode errors.

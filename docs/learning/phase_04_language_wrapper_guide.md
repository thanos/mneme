# Phase 4 Guide: Using the C ABI from Other Languages

This guide is a practical companion to `include/mneme.h` and `docs/design/c_abi.md`.
It focuses on wrapper-facing usage patterns and pitfalls.

## 1) Core Rules (applies to every language)

- Always check each ABI call status (`MNEME_OK` means success).
- On failure, read `mneme_last_error()` on the same thread.
- Free every owned handle:
  - `mneme_collection_free` for collections
  - `mneme_results_free` for result sets
- `mneme_results_id` returns a borrowed pointer; copy it into language-owned memory if needed after results are freed.
- `MNEME_EF_SEARCH_DEFAULT` means "use configured default ef_search" in HNSW search.

## 2) Build/Link Setup

Build native library:

```bash
zig build lib
```

Artifacts:

- macOS: `libmneme.dylib`
- Linux: `libmneme.so`
- header: `include/mneme.h`
- runnable examples:
  - `examples/python/ctypes_basic.py`
  - `examples/rust/ffi_basic.rs`

## 3) Python (`ctypes`) Example

```python
import ctypes
from ctypes import c_uint32, c_uint64, c_float, c_char_p, POINTER, byref

lib = ctypes.CDLL("./zig-out/lib/libmneme.dylib")  # use .so on Linux

class MnemeCollection(ctypes.Structure):
    pass

class MnemeResults(ctypes.Structure):
    pass

MNEME_OK = 0
MNEME_METRIC_COSINE = 1
MNEME_EF_SEARCH_DEFAULT = 0

lib.mneme_collection_create.argtypes = [c_char_p, c_uint32, c_uint32, POINTER(POINTER(MnemeCollection))]
lib.mneme_collection_create.restype = c_uint32
lib.mneme_collection_insert.argtypes = [POINTER(MnemeCollection), c_char_p, POINTER(c_float), c_uint32, c_char_p]
lib.mneme_collection_insert.restype = c_uint32
lib.mneme_collection_search_flat.argtypes = [POINTER(MnemeCollection), POINTER(c_float), c_uint32, c_uint32, POINTER(POINTER(MnemeResults))]
lib.mneme_collection_search_flat.restype = c_uint32
lib.mneme_results_len.argtypes = [POINTER(MnemeResults)]
lib.mneme_results_len.restype = c_uint32
lib.mneme_results_id.argtypes = [POINTER(MnemeResults), c_uint32]
lib.mneme_results_id.restype = c_char_p
lib.mneme_results_free.argtypes = [POINTER(MnemeResults)]
lib.mneme_collection_free.argtypes = [POINTER(MnemeCollection)]
lib.mneme_last_error.restype = c_char_p

def check(status):
    if status != MNEME_OK:
        raise RuntimeError(lib.mneme_last_error().decode("utf-8"))

collection = POINTER(MnemeCollection)()
check(lib.mneme_collection_create(b"docs", 3, MNEME_METRIC_COSINE, byref(collection)))

vec = (c_float * 3)(1.0, 0.0, 0.0)
check(lib.mneme_collection_insert(collection, b"doc_1", vec, 3, None))

results = POINTER(MnemeResults)()
check(lib.mneme_collection_search_flat(collection, vec, 3, 1, byref(results)))
try:
    n = lib.mneme_results_len(results)
    ids = [lib.mneme_results_id(results, i).decode("utf-8") for i in range(n)]  # copy to Python str
    print(ids)
finally:
    lib.mneme_results_free(results)
    lib.mneme_collection_free(collection)
```

## 4) Python (`cffi`) Sketch

```python
from cffi import FFI

ffi = FFI()
ffi.cdef(open("include/mneme.h").read())
lib = ffi.dlopen("./zig-out/lib/libmneme.dylib")  # .so on Linux

out = ffi.new("mneme_collection_t **")
rc = lib.mneme_collection_create(b"docs", 3, lib.MNEME_METRIC_COSINE, out)
if rc != lib.MNEME_OK:
    raise RuntimeError(ffi.string(lib.mneme_last_error()).decode())
```

Use cffi for easier C declarations and less manual `argtypes` bookkeeping.

## 5) Rust FFI Sketch

```rust
#[repr(C)]
pub struct mneme_collection_t { _private: [u8; 0] }
#[repr(C)]
pub struct mneme_results_t { _private: [u8; 0] }

extern "C" {
    fn mneme_collection_create(
        name: *const std::os::raw::c_char,
        dimension: u32,
        metric: u32,
        out: *mut *mut mneme_collection_t,
    ) -> u32;
    fn mneme_collection_free(c: *mut mneme_collection_t);
}
```

Recommended wrapper style in Rust:

- raw `extern \"C\"` module
- safe RAII wrapper struct (`Drop` calls free)
- convert borrowed ids to owned `String` before freeing results
- map status codes to `Result<T, Error>`

## 6) Elixir Integration (Port/NIF) Guidance

- Port approach:
  - keep ABI interaction in a small external executable
  - exchange messages over stdin/stdout
  - easier fault isolation
- NIF approach:
  - wrap handles as resource objects
  - call `mneme_collection_free`/`mneme_results_free` in resource destructors
  - avoid long blocking calls on scheduler threads (save/build/search on large sets)

## 7) Wrapper Ergonomics Recommendations

- Build language-level result objects that copy ids immediately.
- Expose `ef_search` optional arg; map missing/`None` to `MNEME_EF_SEARCH_DEFAULT`.
- For bulk ingest, use `mneme_collection_insert_batch`.
- Wrap errors with both status code and `mneme_last_error()` text.

## 8) Threading Notes for Wrappers

- `mneme_last_error` is thread-local.
- Calls on the same collection handle are serialized by ABI lock.
- Do not call `mneme_collection_free` while other calls are in-flight on that handle.

## 9) Wrapper Ecosystem Notes (Phase 5 planning)

Given planned wrapper/tooling direction, keep the ABI ergonomics centered on:

- stable C signatures + explicit ownership (`create/load/search allocate`, caller frees)
- predictable status mapping and thread-local last-error reads on the same thread
- optional out-parameters where supported (`out_inserted` / `out_deleted`)

Specific notes for planned stack:

- **PyOZ**: keep C ABI examples small and deterministic so Python extension wrappers can map status/ownership clearly.
- **zigler**: favor explicit resource-lifetime contracts and non-blocking guidance for long operations when called from managed runtimes.
- **Zigar** and **zig-build**: keep build/link instructions platform-explicit (`.dylib` vs `.so`, runtime search path expectations) to reduce integration friction across JS/native pipelines.

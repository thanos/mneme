# Phase 5 Learning: ABI Design Lessons

## 1) Output Pointers Must Be Defensive

For `out_*` parameters, clearing outputs early avoids stale-pointer bugs on error paths.

Pattern:

- if out pointer is non-null, set `*out = null`
- validate inputs
- return error status if invalid

This prevents callers from accidentally reusing old handles/results.

## 2) Error Handling Must Be Predictable

Status mapping should be boring and stable:

- invalid arguments -> `MNEME_ERROR_INVALID_ARGUMENT`
- dimension mismatch -> `MNEME_ERROR_DIMENSION_MISMATCH`
- IO issues -> `MNEME_ERROR_IO`
- HNSW not built/stale -> specific index errors

Predictable mapping is wrapper ergonomics.

## 3) Threading Contracts Need Explicit Scope

The C ABI currently serializes per-handle operations and uses thread-local `mneme_last_error`.
This is practical for correctness and safer wrapper integration than undocumented shared state.

## 4) Long Operations Should Minimize Lock Hold Time

Saving/building with lock held across full work creates avoidable contention.
Snapshot-under-lock + perform heavy work after unlock is a practical compromise.

## 5) Additive ABI Changes Still Need Discovery Strategy

Keeping ABI version constant for additive symbols is fine, but wrappers need feature detection.
A maintained symbol matrix + runtime probing keeps wrapper behavior robust.

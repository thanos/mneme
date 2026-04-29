#!/usr/bin/env python3
"""
Minimal runnable ctypes example for mneme C ABI.

Usage (from repo root):
  zig build lib
  python3 examples/python/ctypes_basic.py

Env override:
  MNEME_LIB_PATH=/custom/path/to/libmneme.so python3 examples/python/ctypes_basic.py
"""

import ctypes
import os
import platform
from ctypes import POINTER, byref, c_char_p, c_float, c_uint32


def default_library_path() -> str:
    system = platform.system()
    if system == "Darwin":
        return "./zig-out/lib/libmneme.dylib"
    if system == "Linux":
        return "./zig-out/lib/libmneme.so"
    raise RuntimeError(f"Unsupported OS for this example: {system}")


LIB_PATH = os.environ.get("MNEME_LIB_PATH", default_library_path())
lib = ctypes.CDLL(LIB_PATH)


class MnemeCollection(ctypes.Structure):
    pass


class MnemeResults(ctypes.Structure):
    pass


MNEME_OK = 0
MNEME_METRIC_COSINE = 1


lib.mneme_collection_create.argtypes = [
    c_char_p,
    c_uint32,
    c_uint32,
    POINTER(POINTER(MnemeCollection)),
]
lib.mneme_collection_create.restype = c_uint32

lib.mneme_collection_insert.argtypes = [
    POINTER(MnemeCollection),
    c_char_p,
    POINTER(c_float),
    c_uint32,
    c_char_p,
]
lib.mneme_collection_insert.restype = c_uint32

lib.mneme_collection_search_flat.argtypes = [
    POINTER(MnemeCollection),
    POINTER(c_float),
    c_uint32,
    c_uint32,
    POINTER(POINTER(MnemeResults)),
]
lib.mneme_collection_search_flat.restype = c_uint32

lib.mneme_results_len.argtypes = [POINTER(MnemeResults)]
lib.mneme_results_len.restype = c_uint32

lib.mneme_results_id.argtypes = [POINTER(MnemeResults), c_uint32]
lib.mneme_results_id.restype = c_char_p

lib.mneme_results_free.argtypes = [POINTER(MnemeResults)]
lib.mneme_results_free.restype = None

lib.mneme_collection_free.argtypes = [POINTER(MnemeCollection)]
lib.mneme_collection_free.restype = None

lib.mneme_last_error.argtypes = []
lib.mneme_last_error.restype = c_char_p


def check(status: int) -> None:
    if status != MNEME_OK:
        message = lib.mneme_last_error().decode("utf-8")
        raise RuntimeError(f"mneme call failed ({status}): {message}")


def main() -> None:
    collection = POINTER(MnemeCollection)()
    check(lib.mneme_collection_create(b"docs", 3, MNEME_METRIC_COSINE, byref(collection)))

    try:
        vector = (c_float * 3)(1.0, 0.0, 0.0)
        check(lib.mneme_collection_insert(collection, b"doc_1", vector, 3, b"source=python"))

        results = POINTER(MnemeResults)()
        check(lib.mneme_collection_search_flat(collection, vector, 3, 1, byref(results)))
        try:
            length = lib.mneme_results_len(results)
            ids = [lib.mneme_results_id(results, i).decode("utf-8") for i in range(length)]
            print("top ids:", ids)
        finally:
            lib.mneme_results_free(results)
    finally:
        lib.mneme_collection_free(collection)


if __name__ == "__main__":
    main()

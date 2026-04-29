//! Minimal Rust FFI example for mneme C ABI.
//!
//! Build library first:
//!   zig build lib
//!
//! Compile (Linux):
//!   rustc examples/rust/ffi_basic.rs -L zig-out/lib -l dylib=mneme -o /tmp/mneme_rust_example
//!   LD_LIBRARY_PATH=zig-out/lib /tmp/mneme_rust_example
//!
//! Compile (macOS):
//!   rustc examples/rust/ffi_basic.rs -L zig-out/lib -l dylib=mneme -o /tmp/mneme_rust_example
//!   DYLD_LIBRARY_PATH=zig-out/lib /tmp/mneme_rust_example

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_float, c_uint};
use std::ptr;

#[repr(C)]
pub struct mneme_collection_t {
    _private: [u8; 0],
}

#[repr(C)]
pub struct mneme_results_t {
    _private: [u8; 0],
}

const MNEME_OK: c_uint = 0;
const MNEME_METRIC_COSINE: c_uint = 1;

unsafe extern "C" {
    fn mneme_collection_create(
        name: *const c_char,
        dimension: c_uint,
        metric: c_uint,
        out_collection: *mut *mut mneme_collection_t,
    ) -> c_uint;
    fn mneme_collection_insert(
        collection: *mut mneme_collection_t,
        id: *const c_char,
        vector: *const c_float,
        vector_len: c_uint,
        metadata: *const c_char,
    ) -> c_uint;
    fn mneme_collection_search_flat(
        collection: *mut mneme_collection_t,
        query: *const c_float,
        query_len: c_uint,
        top_k: c_uint,
        out_results: *mut *mut mneme_results_t,
    ) -> c_uint;
    fn mneme_results_len(results: *const mneme_results_t) -> c_uint;
    fn mneme_results_id(results: *const mneme_results_t, index: c_uint) -> *const c_char;
    fn mneme_results_free(results: *mut mneme_results_t);
    fn mneme_collection_free(collection: *mut mneme_collection_t);
    fn mneme_last_error() -> *const c_char;
}

fn check(status: c_uint) -> Result<(), String> {
    if status == MNEME_OK {
        return Ok(());
    }
    unsafe {
        let msg = CStr::from_ptr(mneme_last_error()).to_string_lossy().into_owned();
        Err(format!("mneme call failed ({}): {}", status, msg))
    }
}

fn main() -> Result<(), String> {
    let name = CString::new("docs").unwrap();
    let id = CString::new("doc_1").unwrap();
    let meta = CString::new("source=rust").unwrap();

    let mut collection: *mut mneme_collection_t = ptr::null_mut();
    unsafe {
        check(mneme_collection_create(
            name.as_ptr(),
            3,
            MNEME_METRIC_COSINE,
            &mut collection,
        ))?;
    }

    let vector: [c_float; 3] = [1.0, 0.0, 0.0];
    unsafe {
        check(mneme_collection_insert(
            collection,
            id.as_ptr(),
            vector.as_ptr(),
            3,
            meta.as_ptr(),
        ))?;
    }

    let mut results: *mut mneme_results_t = ptr::null_mut();
    unsafe {
        check(mneme_collection_search_flat(
            collection,
            vector.as_ptr(),
            3,
            1,
            &mut results,
        ))?;
        let n = mneme_results_len(results);
        if n > 0 {
            let first = CStr::from_ptr(mneme_results_id(results, 0))
                .to_string_lossy()
                .into_owned();
            println!("top id: {}", first);
        }
        mneme_results_free(results);
        mneme_collection_free(collection);
    }

    Ok(())
}

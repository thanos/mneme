const std = @import("std");
const mneme = @import("mneme");
const capi = mneme.c_api;
const helpers = @import("storage_test_helpers.zig");

const ParallelSearchCtx = struct {
    collection: *capi.mneme_collection_t,
    query: [3]f32,
    iterations: usize,
    had_error: *std.atomic.Value(bool),
};

const ReaderWriterCtx = struct {
    collection: *capi.mneme_collection_t,
    had_error: *std.atomic.Value(bool),
};

const BuildRaceCtx = struct {
    collection: *capi.mneme_collection_t,
    done: *std.atomic.Value(bool),
    had_error: *std.atomic.Value(bool),
    next_id: *std.atomic.Value(u32),
};

const ThreadErrorCapture = struct {
    mode: u8,
    buf: [64]u8 = [_]u8{0} ** 64,
    len: usize = 0,
};

fn parallelFlatSearchWorker(ctx: *const ParallelSearchCtx) void {
    var i: usize = 0;
    while (i < ctx.iterations) : (i += 1) {
        var results: ?*capi.mneme_results_t = null;
        const status = capi.mneme_collection_search_flat(ctx.collection, &ctx.query, ctx.query.len, 2, &results);
        if (status != capi.MNEME_OK) {
            ctx.had_error.store(true, .seq_cst);
            return;
        }
        if (results) |r| {
            if (capi.mneme_results_len(r) == 0) {
                ctx.had_error.store(true, .seq_cst);
                capi.mneme_results_free(results);
                return;
            }
        } else {
            ctx.had_error.store(true, .seq_cst);
            return;
        }
        capi.mneme_results_free(results);
    }
}

fn readerWorker(ctx: *const ReaderWriterCtx) void {
    const query = [_]f32{ 1.0, 0.0, 0.0 };
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        var results: ?*capi.mneme_results_t = null;
        const status = capi.mneme_collection_search_flat(ctx.collection, &query, query.len, 3, &results);
        if (status != capi.MNEME_OK) {
            ctx.had_error.store(true, .seq_cst);
            return;
        }
        capi.mneme_results_free(results);
    }
}

fn writerWorker(ctx: *const ReaderWriterCtx) void {
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        var id_buf: [32:0]u8 = undefined;
        const id = std.fmt.bufPrintSentinel(&id_buf, "w_{d}", .{i}, 0) catch {
            ctx.had_error.store(true, .seq_cst);
            return;
        };
        const v = [_]f32{ 1.0, @as(f32, @floatFromInt(@mod(i, 10))) / 10.0, 0.0 };
        const status = capi.mneme_collection_insert(ctx.collection, id.ptr, &v, v.len, null);
        if (status != capi.MNEME_OK) {
            ctx.had_error.store(true, .seq_cst);
            return;
        }
    }
}

fn buildRaceWriterWorker(ctx: *const BuildRaceCtx) void {
    while (!ctx.done.load(.seq_cst)) {
        const id_num = ctx.next_id.fetchAdd(1, .seq_cst);
        var id_buf: [32:0]u8 = undefined;
        const id = std.fmt.bufPrintSentinel(&id_buf, "race_{d}", .{id_num}, 0) catch {
            ctx.had_error.store(true, .seq_cst);
            return;
        };
        const v = [_]f32{
            @as(f32, @floatFromInt(@mod(id_num, 29))) / 29.0,
            @as(f32, @floatFromInt(@mod(id_num + 7, 31))) / 31.0,
            0.5,
        };
        const status = capi.mneme_collection_insert(ctx.collection, id.ptr, &v, v.len, null);
        if (status != capi.MNEME_OK) {
            ctx.had_error.store(true, .seq_cst);
            return;
        }
    }
}

fn captureThreadError(capture: *ThreadErrorCapture) void {
    switch (capture.mode) {
        0 => {
            var out: ?*capi.mneme_collection_t = null;
            _ = capi.mneme_collection_create(null, 3, capi.MNEME_METRIC_COSINE, &out);
        },
        else => {
            var out: ?*capi.mneme_collection_t = null;
            _ = capi.mneme_collection_create("docs", 0, capi.MNEME_METRIC_COSINE, &out);
        },
    }
    const msg = std.mem.span(capi.mneme_last_error());
    const n = @min(capture.buf.len, msg.len);
    @memcpy(capture.buf[0..n], msg[0..n]);
    capture.len = n;
}

test "abi version returns nonzero" {
    try std.testing.expect(capi.mneme_abi_version() != 0);
}

test "create and free collection" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    try std.testing.expect(collection != null);
    capi.mneme_collection_free(collection);
}

test "create rejects null out pointer" {
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, null),
    );
}

test "create rejects null name" {
    var collection: ?*capi.mneme_collection_t = @ptrFromInt(1);
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_create(null, 3, capi.MNEME_METRIC_COSINE, &collection),
    );
    try std.testing.expect(collection == null);
}

test "create rejects invalid dimension" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_DIMENSION_MISMATCH,
        capi.mneme_collection_create("docs", 0, capi.MNEME_METRIC_COSINE, &collection),
    );
    try std.testing.expect(collection == null);
}

test "insert point and count works" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vector = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert(collection, "a", &vector, vector.len, "source=test"),
    );
    try std.testing.expectEqual(@as(u64, 1), capi.mneme_collection_count(collection));
}

test "insert batch works and reduces call count" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const ids = [_]?[*:0]const u8{ "a", "b", "c" };
    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
    const metadata = [_]?[*:0]const u8{ "m=a", null, "m=c" };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids, &vectors, 3, &metadata, 3, &inserted),
    );
    try std.testing.expectEqual(@as(u32, 3), inserted);
    try std.testing.expectEqual(@as(u64, 3), capi.mneme_collection_count(collection));
}

test "insert batch allows null out_inserted" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const ids = [_]?[*:0]const u8{ "a", "b" };
    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
    };
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids, &vectors, 3, null, 2, null),
    );
    try std.testing.expectEqual(@as(u64, 2), capi.mneme_collection_count(collection));
}

test "insert batch reports partial progress on null id entry" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const ids = [_]?[*:0]const u8{ "a", null, "c" };
    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_insert_batch(collection, &ids, &vectors, 3, null, 3, &inserted),
    );
    try std.testing.expectEqual(@as(u32, 1), inserted);
    try std.testing.expectEqual(@as(u64, 1), capi.mneme_collection_count(collection));
}

test "insert batch rejects wrong vector_len before slicing payload" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const ids = [_]?[*:0]const u8{ "a", "b" };
    const vectors = [_]f32{ 1.0, 0.0, 0.0 };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_DIMENSION_MISMATCH,
        capi.mneme_collection_insert_batch(collection, &ids, &vectors, 2, null, 2, &inserted),
    );
    try std.testing.expectEqual(@as(u32, 0), inserted);
    try std.testing.expectEqual(@as(u64, 0), capi.mneme_collection_count(collection));
}

test "insert rejects wrong dimension" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vector = [_]f32{ 1.0, 0.0 };
    try std.testing.expectEqual(
        capi.MNEME_ERROR_DIMENSION_MISMATCH,
        capi.mneme_collection_insert(collection, "a", &vector, vector.len, null),
    );
}

test "insert rejects null id" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const vector = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_insert(collection, null, &vector, vector.len, null),
    );
}

test "delete works and missing id maps invalid argument" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vector = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &vector, vector.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_delete(collection, "a"));
    try std.testing.expectEqual(@as(u64, 0), capi.mneme_collection_count(collection));
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_delete(collection, "a"));
}

test "delete batch works and reports partial progress" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
    };
    const ids_insert = [_]?[*:0]const u8{ "a", "b" };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids_insert, &vectors, 3, null, 2, &inserted),
    );

    const ids_delete = [_]?[*:0]const u8{ "a", "missing" };
    var deleted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_delete_batch(collection, &ids_delete, 2, &deleted),
    );
    try std.testing.expectEqual(@as(u32, 1), deleted);
    try std.testing.expectEqual(@as(u64, 1), capi.mneme_collection_count(collection));
}

test "delete batch reports partial progress on null id entry" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
    const ids_insert = [_]?[*:0]const u8{ "a", "b", "c" };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids_insert, &vectors, 3, null, 3, &inserted),
    );
    try std.testing.expectEqual(@as(u32, 3), inserted);

    const ids_delete = [_]?[*:0]const u8{ "a", null, "c" };
    var deleted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_delete_batch(collection, &ids_delete, 3, &deleted),
    );
    try std.testing.expectEqual(@as(u32, 1), deleted);
    try std.testing.expectEqual(@as(u64, 2), capi.mneme_collection_count(collection));
}

test "delete batch allows null out_deleted" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
    };
    const ids_insert = [_]?[*:0]const u8{ "a", "b" };
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids_insert, &vectors, 3, null, 2, null),
    );

    const ids_delete = [_]?[*:0]const u8{ "a", "b" };
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_delete_batch(collection, &ids_delete, 2, null),
    );
    try std.testing.expectEqual(@as(u64, 0), capi.mneme_collection_count(collection));
}

test "flat search works and result access works" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "b", &b, b.len, null));

    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_search_flat(collection, &a, a.len, 2, &results),
    );
    defer capi.mneme_results_free(results);
    try std.testing.expect(results != null);
    try std.testing.expectEqual(@as(u32, 2), capi.mneme_results_len(results));
    const first_id = capi.mneme_results_id(results, 0).?;
    try std.testing.expect(std.mem.eql(u8, std.mem.span(first_id), "a"));
    try std.testing.expect(capi.mneme_results_score(results, 0) >= capi.mneme_results_score(results, 1));
}

test "flat search rejects wrong dimension" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const query = [_]f32{ 1.0, 0.0 };
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_DIMENSION_MISMATCH,
        capi.mneme_collection_search_flat(collection, &query, query.len, 1, &results),
    );
    try std.testing.expect(results == null);
}

test "results free is safe on null" {
    capi.mneme_results_free(null);
}

test "collection free is safe on null" {
    capi.mneme_collection_free(null);
}

test "collection count null returns zero and sets last error" {
    try std.testing.expectEqual(@as(u64, 0), capi.mneme_collection_count(null));
    try std.testing.expect(std.mem.span(capi.mneme_last_error()).len > 0);
}

test "build hnsw works and hnsw search works" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "b", &b, b.len, null));
    const cfg = capi.mneme_hnsw_config_t{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 7 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_build_hnsw(collection, &cfg));

    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_search_hnsw(collection, &a, a.len, 1, 64, &results));
    defer capi.mneme_results_free(results);
    try std.testing.expectEqual(@as(u32, 1), capi.mneme_results_len(results));
}

test "hnsw search before build returns index not built" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const query = [_]f32{ 1.0, 0.0, 0.0 };
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INDEX_NOT_BUILT,
        capi.mneme_collection_search_hnsw(collection, &query, query.len, 1, 64, &results),
    );
}

test "hnsw search ef_search zero uses default" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const cfg = capi.mneme_hnsw_config_t{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 7 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_build_hnsw(collection, &cfg));
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_search_hnsw(collection, &a, a.len, 1, 0, &results),
    );
    defer capi.mneme_results_free(results);
    try std.testing.expectEqual(@as(u32, 1), capi.mneme_results_len(results));
}

test "hnsw search top_k zero returns empty results" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const cfg = capi.mneme_hnsw_config_t{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 11 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_build_hnsw(collection, &cfg));
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_search_hnsw(collection, &a, a.len, 0, capi.MNEME_EF_SEARCH_DEFAULT, &results),
    );
    defer capi.mneme_results_free(results);
    try std.testing.expectEqual(@as(u32, 0), capi.mneme_results_len(results));
}

test "hnsw ef_search default matches explicit default value" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const cfg = capi.mneme_hnsw_config_t{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 42 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "b", &b, b.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_build_hnsw(collection, &cfg));

    var def_results: ?*capi.mneme_results_t = null;
    var explicit_results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_search_hnsw(collection, &a, a.len, 2, capi.MNEME_EF_SEARCH_DEFAULT, &def_results),
    );
    defer capi.mneme_results_free(def_results);
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_search_hnsw(collection, &a, a.len, 2, cfg.ef_search, &explicit_results),
    );
    defer capi.mneme_results_free(explicit_results);
    try std.testing.expectEqual(capi.mneme_results_len(def_results), capi.mneme_results_len(explicit_results));
    const d0 = std.mem.span(capi.mneme_results_id(def_results, 0).?);
    const e0 = std.mem.span(capi.mneme_results_id(explicit_results, 0).?);
    try std.testing.expect(std.mem.eql(u8, d0, e0));
}

test "hnsw stale maps to index stale" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    const cfg = capi.mneme_hnsw_config_t{ .m = 16, .ef_construction = 64, .ef_search = 32, .seed = 7 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_build_hnsw(collection, &cfg));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "b", &b, b.len, null));
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INDEX_STALE,
        capi.mneme_collection_search_hnsw(collection, &a, a.len, 1, 64, &results),
    );
}

test "save through abi, load through abi, search after load works" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &path_buf, "c-api-phase4.mneme");
    const path_z = try std.testing.allocator.dupeSentinel(u8, path, 0);
    defer std.testing.allocator.free(path_z);

    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_save(collection, path_z.ptr));

    var loaded: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_load(path_z.ptr, &loaded));
    defer capi.mneme_collection_free(loaded);
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_search_flat(loaded, &a, a.len, 1, &results));
    defer capi.mneme_results_free(results);
    try std.testing.expectEqual(@as(u32, 1), capi.mneme_results_len(results));
}

test "load missing file maps to io/internal and keeps out null" {
    var out: ?*capi.mneme_collection_t = null;
    const status = capi.mneme_collection_load("/definitely/nonexistent/mneme-file.mneme", &out);
    try std.testing.expect(status == capi.MNEME_ERROR_IO or status == capi.MNEME_ERROR_INTERNAL);
    try std.testing.expect(out == null);
}

test "last error set on failure" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const bad = [_]f32{ 1.0, 0.0 };
    _ = capi.mneme_collection_insert(collection, "a", &bad, bad.len, null);
    const msg = std.mem.span(capi.mneme_last_error());
    try std.testing.expect(msg.len > 0);
}

test "results accessors reject out-of-range index" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_search_flat(collection, &a, a.len, 1, &results));
    defer capi.mneme_results_free(results);
    try std.testing.expect(capi.mneme_results_id(results, 99) == null);
    try std.testing.expectEqual(@as(f32, 0.0), capi.mneme_results_score(results, 99));
}

test "last error is thread-local across worker threads" {
    var one = ThreadErrorCapture{ .mode = 0 };
    var two = ThreadErrorCapture{ .mode = 1 };
    const t1 = try std.Thread.spawn(.{}, captureThreadError, .{&one});
    const t2 = try std.Thread.spawn(.{}, captureThreadError, .{&two});
    t1.join();
    t2.join();
    try std.testing.expect(one.len > 0);
    try std.testing.expect(two.len > 0);
    try std.testing.expect(!std.mem.eql(u8, one.buf[0..one.len], two.buf[0..two.len]));
}

test "null collection arguments rejected" {
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    var flat_results: ?*capi.mneme_results_t = @ptrFromInt(1);
    var hnsw_results: ?*capi.mneme_results_t = @ptrFromInt(1);
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_insert(null, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_delete(null, "a"));
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_search_flat(null, &a, a.len, 1, &flat_results),
    );
    try std.testing.expect(flat_results == null);
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_search_hnsw(
            null,
            &a,
            a.len,
            1,
            capi.MNEME_EF_SEARCH_DEFAULT,
            &hnsw_results,
        ),
    );
    try std.testing.expect(hnsw_results == null);
}

test "duplicate id and invalid hnsw config map to invalid argument" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "a", &a, a.len, null));
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_insert(collection, "a", &a, a.len, null),
    );
    const bad_cfg = capi.mneme_hnsw_config_t{ .m = 0, .ef_construction = 64, .ef_search = 32, .seed = 1 };
    try std.testing.expectEqual(
        capi.MNEME_ERROR_INVALID_ARGUMENT,
        capi.mneme_collection_build_hnsw(collection, &bad_cfg),
    );
}

test "parallel flat searches on same collection are serialized safely" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const ids = [_]?[*:0]const u8{ "a", "b", "c", "d" };
    const vectors = [_]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
        0.7, 0.2, 0.1,
    };
    var inserted: u32 = 0;
    try std.testing.expectEqual(
        capi.MNEME_OK,
        capi.mneme_collection_insert_batch(collection, &ids, &vectors, 3, null, ids.len, &inserted),
    );
    try std.testing.expectEqual(@as(u32, ids.len), inserted);

    var had_error = std.atomic.Value(bool).init(false);
    const ctx = ParallelSearchCtx{
        .collection = collection.?,
        .query = .{ 1.0, 0.0, 0.0 },
        .iterations = 200,
        .had_error = &had_error,
    };

    const t1 = try std.Thread.spawn(.{}, parallelFlatSearchWorker, .{&ctx});
    const t2 = try std.Thread.spawn(.{}, parallelFlatSearchWorker, .{&ctx});
    const t3 = try std.Thread.spawn(.{}, parallelFlatSearchWorker, .{&ctx});
    t1.join();
    t2.join();
    t3.join();

    try std.testing.expect(!had_error.load(.seq_cst));
}

test "parallel insert and flat search on same collection are safe" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    const seed = [_]f32{ 1.0, 0.0, 0.0 };
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, "seed", &seed, seed.len, null));

    var had_error = std.atomic.Value(bool).init(false);
    const ctx = ReaderWriterCtx{
        .collection = collection.?,
        .had_error = &had_error,
    };
    const reader = try std.Thread.spawn(.{}, readerWorker, .{&ctx});
    const writer = try std.Thread.spawn(.{}, writerWorker, .{&ctx});
    reader.join();
    writer.join();

    try std.testing.expect(!had_error.load(.seq_cst));
    try std.testing.expect(capi.mneme_collection_count(collection) >= 1);
}

test "build hnsw races with writes and reports index stale" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);

    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var id_buf: [32:0]u8 = undefined;
        const id = try std.fmt.bufPrintSentinel(&id_buf, "seed_{d}", .{i}, 0);
        const v = [_]f32{
            @as(f32, @floatFromInt(@mod(i, 17))) / 17.0,
            @as(f32, @floatFromInt(@mod(i + 5, 19))) / 19.0,
            1.0,
        };
        try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_insert(collection, id.ptr, &v, v.len, null));
    }

    var done = std.atomic.Value(bool).init(false);
    var had_error = std.atomic.Value(bool).init(false);
    var next_id = std.atomic.Value(u32).init(100_000);
    const build_ctx = BuildRaceCtx{
        .collection = collection.?,
        .done = &done,
        .had_error = &had_error,
        .next_id = &next_id,
    };
    const writer_thread = try std.Thread.spawn(.{}, buildRaceWriterWorker, .{&build_ctx});
    defer {
        done.store(true, .seq_cst);
        writer_thread.join();
    }

    // Try multiple builds while the writer thread is mutating.
    const cfg = capi.mneme_hnsw_config_t{
        .m = 16,
        .ef_construction = 64,
        .ef_search = 32,
        .seed = 13,
    };
    var stale_seen = false;
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        const status = capi.mneme_collection_build_hnsw(collection, &cfg);
        if (status == capi.MNEME_ERROR_INDEX_STALE) {
            stale_seen = true;
            break;
        }
        try std.testing.expectEqual(capi.MNEME_OK, status);
    }

    done.store(true, .seq_cst);

    try std.testing.expect(!had_error.load(.seq_cst));
    try std.testing.expect(stale_seen);
}

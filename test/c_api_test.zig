const std = @import("std");
const mneme = @import("mneme");
const capi = mneme.c_api;
const helpers = @import("storage_test_helpers.zig");

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

test "last error set on failure" {
    var collection: ?*capi.mneme_collection_t = null;
    try std.testing.expectEqual(capi.MNEME_OK, capi.mneme_collection_create("docs", 3, capi.MNEME_METRIC_COSINE, &collection));
    defer capi.mneme_collection_free(collection);
    const bad = [_]f32{ 1.0, 0.0 };
    _ = capi.mneme_collection_insert(collection, "a", &bad, bad.len, null);
    const msg = std.mem.span(capi.mneme_last_error());
    try std.testing.expect(msg.len > 0);
}

test "null collection arguments rejected" {
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    var results: ?*capi.mneme_results_t = null;
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_insert(null, "a", &a, a.len, null));
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_delete(null, "a"));
    try std.testing.expectEqual(capi.MNEME_ERROR_INVALID_ARGUMENT, capi.mneme_collection_search_flat(null, &a, a.len, 1, &results));
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

const std = @import("std");
const mneme = @import("mneme");
const helpers = @import("storage_test_helpers.zig");

test "searchWithOptions hnsw without build returns IndexNotBuilt" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try std.testing.expectError(
        mneme.MnemeError.IndexNotBuilt,
        c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw }),
    );
}

test "collection buildHnsw and searchWithOptions hnsw works" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.insert("b", &[_]f32{ 0.0, 1.0, 0.0 }, null);
    try c.buildHnsw(.{ .seed = 7 });

    const results = try c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw });
    defer c.freeSearchResults(results);
    try std.testing.expectEqual(@as(usize, 1), results.len);
}

test "searchWithOptions flat matches search path" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.insert("b", &[_]f32{ 0.9, 0.1, 0.0 }, null);
    const query = [_]f32{ 1.0, 0.0, 0.0 };

    const base = try c.search(&query, 2);
    defer c.freeSearchResults(base);
    const with_options = try c.searchWithOptions(&query, 2, .{ .index = .flat });
    defer c.freeSearchResults(with_options);

    try std.testing.expectEqual(base.len, with_options.len);
    for (base, with_options) |left, right| {
        try std.testing.expect(std.mem.eql(u8, left.id, right.id));
        try std.testing.expectEqual(left.score, right.score);
    }
}

test "insert and delete after build mark hnsw stale" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.buildHnsw(.{});

    try c.insert("b", &[_]f32{ 0.0, 1.0, 0.0 }, null);
    try std.testing.expectError(
        mneme.MnemeError.IndexStale,
        c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw }),
    );

    try c.buildHnsw(.{});
    try c.delete("a");
    try std.testing.expectError(
        mneme.MnemeError.IndexStale,
        c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw }),
    );

    try c.buildHnsw(.{});
    const rebuilt_results = try c.searchWithOptions(&[_]f32{ 0.0, 1.0, 0.0 }, 1, .{ .index = .hnsw });
    defer c.freeSearchResults(rebuilt_results);
    try std.testing.expectEqual(@as(usize, 1), rebuilt_results.len);
    try std.testing.expect(std.mem.eql(u8, "b", rebuilt_results[0].id));
}

test "hnsw search rejects explicit ef_search zero" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.buildHnsw(.{});
    try std.testing.expectError(
        mneme.MnemeError.InvalidEfSearch,
        c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw, .ef_search = 0 }),
    );
}

test "hnsw-built empty collection returns empty results" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.buildHnsw(.{});
    const results = try c.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 5, .{ .index = .hnsw });
    defer c.freeSearchResults(results);
    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "loadFromFile does not load hnsw but can rebuild it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &path_buf, "phase3-load.mneme");

    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();
    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.buildHnsw(.{});
    try c.saveToFile(path);

    var loaded = try mneme.Collection.loadFromFile(std.testing.allocator, path);
    defer loaded.deinit();

    try std.testing.expectError(
        mneme.MnemeError.IndexNotBuilt,
        loaded.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw }),
    );

    try loaded.buildHnsw(.{});
    const results = try loaded.searchWithOptions(&[_]f32{ 1.0, 0.0, 0.0 }, 1, .{ .index = .hnsw });
    defer loaded.freeSearchResults(results);
    try std.testing.expectEqual(@as(usize, 1), results.len);
}

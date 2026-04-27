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

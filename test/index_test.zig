const std = @import("std");
const mneme = @import("mneme");

test "flat index scans points and returns top-k" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const c = [_]f32{ 0.7, 0.3, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, null);
    try collection.insert("c", &c, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try mneme.FlatIndex.search(
        std.testing.allocator,
        collection.points.items,
        &query,
        2,
        .cosine,
    );
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
    try std.testing.expect(std.mem.eql(u8, "c", results[1].id));
}

test "top-k larger than available data works" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("a", &a, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try mneme.FlatIndex.search(
        std.testing.allocator,
        collection.points.items,
        &query,
        10,
        .cosine,
    );
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
}

const std = @import("std");
const mneme = @import("mneme");

fn insertOnceNoLeak(allocator: std.mem.Allocator) !void {
    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");
}

fn pointInitNoLeak(allocator: std.mem.Allocator) !void {
    var point = try mneme.Point.init(allocator, "doc_1", &[_]f32{ 1.0, 0.0, 0.0 }, "source=chat");
    defer point.deinit(allocator);
}

test "create collection" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    try std.testing.expectEqual(@as(usize, 0), collection.count());
}

test "point init handles allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pointInitNoLeak, .{});
}

test "insert handles allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, insertOnceNoLeak, .{});
}

test "reject zero dimension collection" {
    try std.testing.expectError(
        mneme.MnemeError.InvalidDimension,
        mneme.Collection.init(std.testing.allocator, "docs", 0, .cosine),
    );
}

test "insert point and count points" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");
    try std.testing.expectEqual(@as(usize, 1), collection.count());
}

test "reject duplicate id" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, null);
    try std.testing.expectError(mneme.MnemeError.DuplicateId, collection.insert("doc_1", &v, null));
}

test "reject wrong-dimension vector" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const bad = [_]f32{ 1.0, 2.0 };
    try std.testing.expectError(mneme.MnemeError.InvalidDimension, collection.insert("bad", &bad, null));
}

test "delete missing point fails" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    try std.testing.expectError(mneme.MnemeError.IdNotFound, collection.delete("missing"));
}

test "delete point" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, null);
    try std.testing.expectEqual(@as(usize, 1), collection.count());

    try collection.delete("doc_1");
    try std.testing.expectEqual(@as(usize, 0), collection.count());
}

test "delete and re-insert same id works" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, null);
    try collection.delete("doc_1");
    try collection.insert("doc_1", &v, null);
    try std.testing.expectEqual(@as(usize, 1), collection.count());
}

test "search empty collection" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try collection.search(&query, 10);
    defer collection.freeSearchResults(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "search returns top-k ordered results" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const c = [_]f32{ 0.8, 0.2, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, null);
    try collection.insert("c", &c, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try collection.search(&query, 2);
    defer collection.freeSearchResults(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
    try std.testing.expect(std.mem.eql(u8, "c", results[1].id));
    try std.testing.expect(results[0].score >= results[1].score);
}

test "search with top-k zero returns empty results" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("a", &a, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try collection.search(&query, 0);
    defer collection.freeSearchResults(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "search result ids remain valid after collection mutation" {
    var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("a", &a, null);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try collection.search(&query, 1);
    defer collection.freeSearchResults(results);

    try collection.delete("a");
    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
}

test "search result ids remain valid after collection deinit" {
    var results: []mneme.SearchResult = undefined;
    {
        var collection = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
        defer collection.deinit();

        const a = [_]f32{ 1.0, 0.0, 0.0 };
        try collection.insert("a", &a, null);

        const query = [_]f32{ 1.0, 0.0, 0.0 };
        results = try collection.search(&query, 1);
    }
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, results);

    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
}

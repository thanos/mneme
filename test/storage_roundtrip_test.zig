const std = @import("std");
const mneme = @import("mneme");
const helpers = @import("storage_test_helpers.zig");

test "save and load empty collection" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_empty.mneme");
    defer helpers.deleteFile(path);

    var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 0), loaded.count());
    try std.testing.expectEqual(@as(usize, 3), loaded.dimension);
    try std.testing.expectEqual(mneme.Metric.cosine, loaded.metric);

    var loaded_data = try helpers.saveLoadRaw(path, allocator);
    defer loaded_data.deinit();
    try std.testing.expect(std.mem.eql(u8, "docs", loaded_data.name));
}

test "save and load one point metadata and search" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_one.mneme");
    defer helpers.deleteFile(path);

    var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded.count());
    try std.testing.expectEqual(@as(usize, 3), loaded.dimension);
    try std.testing.expectEqual(mneme.Metric.cosine, loaded.metric);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try loaded.search(&query, 1);
    defer loaded.freeSearchResults(results);
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(std.mem.eql(u8, "doc_1", results[0].id));

    var loaded_data = try helpers.saveLoadRaw(path, allocator);
    defer loaded_data.deinit();
    try std.testing.expectEqualSlices(f32, &v, loaded_data.points.items[0].vector);
}

test "metadata round trip via storage load" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_metadata.mneme");
    defer helpers.deleteFile(path);

    try collection.saveToFile(path);
    var loaded_data = try helpers.saveLoadRaw(path, allocator);
    defer loaded_data.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded_data.points.items.len);
    try std.testing.expect(loaded_data.points.items[0].metadata != null);
    try std.testing.expect(std.mem.eql(u8, "source=chat", loaded_data.points.items[0].metadata.?));
}

test "save and load many points" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const c = [_]f32{ 0.7, 0.3, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, "cat=b");
    try collection.insert("c", &c, null);

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_many.mneme");
    defer helpers.deleteFile(path);

    var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 3), loaded.count());

    var loaded_data = try helpers.saveLoadRaw(path, allocator);
    defer loaded_data.deinit();
    try std.testing.expectEqual(@as(usize, 3), loaded_data.points.items.len);
    try std.testing.expect(loaded_data.points.items[0].metadata == null);
    try std.testing.expect(loaded_data.points.items[1].metadata != null);
    try std.testing.expect(std.mem.eql(u8, "cat=b", loaded_data.points.items[1].metadata.?));
    try std.testing.expect(loaded_data.points.items[2].metadata == null);
}

test "delete then save and load preserves state" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, null);
    try collection.delete("a");

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_delete.mneme");
    defer helpers.deleteFile(path);

    var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded.count());
    const query = [_]f32{ 0.0, 1.0, 0.0 };
    const results = try loaded.search(&query, 1);
    defer loaded.freeSearchResults(results);
    try std.testing.expect(std.mem.eql(u8, "b", results[0].id));
}

test "save-load search equivalence" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 4, .cosine);
    defer collection.deinit();
    try collection.insert("a", &[_]f32{ 1, 0, 0, 0 }, null);
    try collection.insert("b", &[_]f32{ 0, 1, 0, 0 }, "m=b");
    try collection.insert("c", &[_]f32{ 0.5, 0.5, 0, 0 }, null);

    const query = [_]f32{ 1, 0, 0, 0 };
    const before = try collection.search(&query, 3);
    defer collection.freeSearchResults(before);

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&buf, "storage_equiv.mneme");
    defer helpers.deleteFile(path);
    var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
    defer loaded.deinit();
    const after = try loaded.search(&query, 3);
    defer loaded.freeSearchResults(after);

    try std.testing.expectEqual(before.len, after.len);
    for (before, after) |left, right| {
        try std.testing.expect(std.mem.eql(u8, left.id, right.id));
        try std.testing.expectApproxEqAbs(left.score, right.score, 0.00001);
    }
}

test "randomized persistence round-trip preserves search and payloads" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var prng = std.Random.DefaultPrng.init(0x1234_5678_9ABC_DEF0);
    const random = prng.random();

    var case_index: usize = 0;
    while (case_index < 12) : (case_index += 1) {
        const dimension: usize = random.intRangeAtMost(usize, 2, 8);
        const point_count: usize = random.intRangeAtMost(usize, 1, 20);

        var collection = try mneme.Collection.init(allocator, "fuzz", dimension, .cosine);
        defer collection.deinit();

        var inserted = std.ArrayList(struct {
            id: [32]u8,
            len: usize,
            metadata: ?[]const u8,
            vector: []f32,
        }).empty;
        defer {
            for (inserted.items) |item| allocator.free(item.vector);
            inserted.deinit(allocator);
        }

        var i: usize = 0;
        while (i < point_count) : (i += 1) {
            var id_buf: [32]u8 = undefined;
            const id = try std.fmt.bufPrint(&id_buf, "p_{d}_{d}", .{ case_index, i });

            const vec = try allocator.alloc(f32, dimension);
            for (vec) |*value| {
                value.* = random.float(f32) * 2.0 - 1.0;
            }
            const metadata: ?[]const u8 = if (i % 2 == 0) null else "tag=random";
            try collection.insert(id, vec, metadata);
            try inserted.append(allocator, .{
                .id = id_buf,
                .len = id.len,
                .metadata = metadata,
                .vector = vec,
            });
        }

        const query = try allocator.alloc(f32, dimension);
        defer allocator.free(query);
        for (query) |*value| {
            value.* = random.float(f32) * 2.0 - 1.0;
        }

        const expected = try collection.search(query, @min(@as(usize, 5), point_count));
        defer collection.freeSearchResults(expected);

        var path_buf: [256]u8 = undefined;
        const path = try helpers.testPath(&path_buf, "storage_fuzz_case.mneme");
        defer helpers.deleteFile(path);
        var loaded = try helpers.saveLoadCollection(allocator, &collection, path);
        defer loaded.deinit();
        const actual = try loaded.search(query, @min(@as(usize, 5), point_count));
        defer loaded.freeSearchResults(actual);

        try std.testing.expectEqual(expected.len, actual.len);
        for (expected, actual) |left, right| {
            try std.testing.expect(std.mem.eql(u8, left.id, right.id));
            try std.testing.expectApproxEqAbs(left.score, right.score, 0.00001);
        }

        var loaded_data = try helpers.saveLoadRaw(path, allocator);
        defer loaded_data.deinit();
        try std.testing.expectEqual(point_count, loaded_data.points.items.len);
        for (loaded_data.points.items, 0..) |point, idx| {
            const expected_item = inserted.items[idx];
            try std.testing.expect(std.mem.eql(u8, point.id, expected_item.id[0..expected_item.len]));
            if (expected_item.metadata) |metadata| {
                try std.testing.expect(point.metadata != null);
                try std.testing.expect(std.mem.eql(u8, metadata, point.metadata.?));
            } else {
                try std.testing.expect(point.metadata == null);
            }
            try std.testing.expectEqualSlices(f32, expected_item.vector, point.vector);
        }
    }
}

const std = @import("std");
const mneme = @import("mneme");

fn buildPoint(allocator: std.mem.Allocator, id: []const u8, v: []const f32) !mneme.Point {
    return mneme.Point.init(allocator, id, v, null);
}

test "hnsw invalid config rejected" {
    try std.testing.expectError(
        mneme.MnemeError.InvalidIndexConfig,
        mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .m = 0 }),
    );
    try std.testing.expectError(
        mneme.MnemeError.InvalidIndexConfig,
        mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .m = 8, .ef_construction = 4 }),
    );
}

test "hnsw build empty and search returns empty" {
    var index = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{});
    defer index.deinit();

    const points = [_]mneme.Point{};
    try index.build(&points);
    try std.testing.expect(index.entry == null);

    const q = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try index.search(&points, &q, 3, null);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, results);
    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "hnsw build one-point collection returns that point" {
    var point = try buildPoint(std.testing.allocator, "a", &[_]f32{ 1.0, 0.0, 0.0 });
    defer point.deinit(std.testing.allocator);
    const points = [_]mneme.Point{point};

    var index = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{});
    defer index.deinit();
    try index.build(&points);
    try std.testing.expect(index.entry != null);

    const q = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try index.search(&points, &q, 1, null);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, results);
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(std.mem.eql(u8, "a", results[0].id));
}

test "hnsw random levels stay within cap and stats are coherent" {
    var points_buf: [128]mneme.Point = undefined;
    var idx: usize = 0;
    errdefer while (idx > 0) : (idx -= 1) points_buf[idx - 1].deinit(std.testing.allocator);
    while (idx < points_buf.len) : (idx += 1) {
        var id_buf: [24]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "cap_{d}", .{idx});
        const v = [_]f32{ 1.0, @as(f32, @floatFromInt(idx + 1)), 0.5 };
        points_buf[idx] = try buildPoint(std.testing.allocator, id, &v);
    }
    defer {
        for (&points_buf) |*p| p.deinit(std.testing.allocator);
    }

    var index = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 123 });
    defer index.deinit();
    try index.build(&points_buf);

    for (index.nodes.items) |node| {
        try std.testing.expect(node.level <= 32);
    }

    var stats = try index.stats(std.testing.allocator);
    defer stats.deinit();
    try std.testing.expectEqual(index.nodes.items.len, stats.node_count);
    if (stats.max_level >= 0) {
        try std.testing.expectEqual(@as(usize, @intCast(stats.max_level)) + 1, stats.level_counts.len);
    } else {
        try std.testing.expectEqual(@as(usize, 0), stats.level_counts.len);
    }
}

test "hnsw deterministic results across rebuild with same seed" {
    var points_buf: [12]mneme.Point = undefined;
    var idx: usize = 0;
    errdefer while (idx > 0) : (idx -= 1) points_buf[idx - 1].deinit(std.testing.allocator);
    while (idx < points_buf.len) : (idx += 1) {
        var id_buf: [24]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "det_{d}", .{idx});
        const v = [_]f32{
            @as(f32, @floatFromInt((idx * 3) + 1)),
            @as(f32, @floatFromInt((idx * 5) + 2)),
            @as(f32, @floatFromInt((idx * 7) + 3)),
        };
        points_buf[idx] = try buildPoint(std.testing.allocator, id, &v);
    }
    defer {
        for (&points_buf) |*p| p.deinit(std.testing.allocator);
    }

    var a = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 77 });
    defer a.deinit();
    var b = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 77 });
    defer b.deinit();
    try a.build(&points_buf);
    try b.build(&points_buf);

    const query = [_]f32{ 1.0, 1.0, 1.0 };
    const a_results = try a.search(&points_buf, &query, 5, 64);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, a_results);
    const b_results = try b.search(&points_buf, &query, 5, 64);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, b_results);

    try std.testing.expectEqual(a_results.len, b_results.len);
    for (a_results, b_results) |left, right| {
        try std.testing.expect(std.mem.eql(u8, left.id, right.id));
        try std.testing.expectEqual(left.score, right.score);
    }
}

test "hnsw direct insert API works standalone" {
    var points = [_]mneme.Point{
        try buildPoint(std.testing.allocator, "a", &[_]f32{ 1.0, 0.0, 0.0 }),
        try buildPoint(std.testing.allocator, "b", &[_]f32{ 0.0, 1.0, 0.0 }),
        try buildPoint(std.testing.allocator, "c", &[_]f32{ 0.0, 0.0, 1.0 }),
    };
    defer {
        for (&points) |*p| p.deinit(std.testing.allocator);
    }

    var index = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 5 });
    defer index.deinit();
    try index.insert(&points, 0, points[0].vector);
    try index.insert(&points, 1, points[1].vector);
    try index.insert(&points, 2, points[2].vector);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try index.search(&points, &query, 2, null);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, results);
    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "hnsw deterministic level generation with seed" {
    var points_buf: [8]mneme.Point = undefined;
    var idx: usize = 0;
    errdefer while (idx > 0) : (idx -= 1) points_buf[idx - 1].deinit(std.testing.allocator);
    while (idx < points_buf.len) : (idx += 1) {
        var id_buf: [16]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "p_{d}", .{idx});
        const v = [_]f32{ @as(f32, @floatFromInt(idx + 1)), 1.0, 1.0 };
        points_buf[idx] = try buildPoint(std.testing.allocator, id, &v);
    }
    defer {
        for (&points_buf) |*p| p.deinit(std.testing.allocator);
    }

    var a = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 9 });
    defer a.deinit();
    var b = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 9 });
    defer b.deinit();
    try a.build(&points_buf);
    try b.build(&points_buf);

    try std.testing.expectEqual(a.nodes.items.len, b.nodes.items.len);
    for (a.nodes.items, b.nodes.items) |left, right| {
        try std.testing.expectEqual(left.level, right.level);
    }
}

test "hnsw search top-k sorted and query dimension mismatch fails" {
    var points = [_]mneme.Point{
        try buildPoint(std.testing.allocator, "a", &[_]f32{ 1.0, 0.0, 0.0 }),
        try buildPoint(std.testing.allocator, "b", &[_]f32{ 0.9, 0.1, 0.0 }),
        try buildPoint(std.testing.allocator, "c", &[_]f32{ 0.0, 1.0, 0.0 }),
    };
    defer {
        for (&points) |*p| p.deinit(std.testing.allocator);
    }

    var index = try mneme.internal.HnswIndex.init(std.testing.allocator, 3, .cosine, .{ .seed = 42 });
    defer index.deinit();
    try index.build(&points);

    const q = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try index.search(&points, &q, 2, null);
    defer mneme.FlatIndex.freeSearchResults(std.testing.allocator, results);
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expect(results[0].score >= results[1].score);

    const bad_q = [_]f32{ 1.0, 0.0 };
    try std.testing.expectError(mneme.MnemeError.InvalidDimension, index.search(&points, &bad_q, 2, null));
}

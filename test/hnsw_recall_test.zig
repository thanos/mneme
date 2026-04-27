const std = @import("std");
const mneme = @import("mneme");

test "hnsw top-1 matches flat on simple dataset" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 3, .cosine);
    defer c.deinit();

    try c.insert("a", &[_]f32{ 1.0, 0.0, 0.0 }, null);
    try c.insert("b", &[_]f32{ 0.9, 0.1, 0.0 }, null);
    try c.insert("c", &[_]f32{ 0.0, 1.0, 0.0 }, null);

    try c.buildHnsw(.{ .m = 8, .ef_construction = 32, .ef_search = 16, .seed = 42 });

    const q = [_]f32{ 1.0, 0.0, 0.0 };
    const flat = try c.search(&q, 1);
    defer c.freeSearchResults(flat);
    const ann = try c.searchWithOptions(&q, 1, .{ .index = .hnsw });
    defer c.freeSearchResults(ann);

    try std.testing.expectEqual(@as(usize, 1), ann.len);
    try std.testing.expect(std.mem.eql(u8, flat[0].id, ann[0].id));
}

test "hnsw top-k has substantial overlap with flat" {
    var c = try mneme.Collection.init(std.testing.allocator, "docs", 16, .cosine);
    defer c.deinit();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        var v: [16]f32 = undefined;
        for (&v, 0..) |*slot, j| {
            const raw = ((i * 31) + (j * 17)) % 101;
            slot.* = @as(f32, @floatFromInt(raw)) / 101.0;
        }
        var id_buf: [32]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "id_{d}", .{i});
        try c.insert(id, &v, null);
    }

    try c.buildHnsw(.{ .m = 16, .ef_construction = 128, .ef_search = 64, .seed = 99 });

    var q: [16]f32 = undefined;
    for (&q, 0..) |*slot, j| {
        slot.* = @as(f32, @floatFromInt((j * 7) % 29)) / 29.0;
    }

    const flat = try c.search(&q, 10);
    defer c.freeSearchResults(flat);
    const ann = try c.searchWithOptions(&q, 10, .{ .index = .hnsw, .ef_search = 64 });
    defer c.freeSearchResults(ann);

    var overlap: usize = 0;
    for (ann) |a| {
        for (flat) |f| {
            if (std.mem.eql(u8, a.id, f.id)) {
                overlap += 1;
                break;
            }
        }
    }
    try std.testing.expect(overlap >= 7);
}

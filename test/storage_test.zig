const std = @import("std");
const mneme = @import("mneme");

fn testPath(buf: *[256]u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, ".zig-cache/{s}", .{name});
}

test "save and load empty collection" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_empty.mneme");

    try collection.saveToFile(path);
    var loaded = try mneme.Collection.loadFromFile(allocator, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 0), loaded.count());
    try std.testing.expectEqual(@as(usize, 3), loaded.dimension);
    try std.testing.expectEqual(mneme.Metric.cosine, loaded.metric);
}

test "save and load one point metadata and search" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");

    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_one.mneme");

    try collection.saveToFile(path);
    var loaded = try mneme.Collection.loadFromFile(allocator, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded.count());
    try std.testing.expectEqual(@as(usize, 3), loaded.dimension);
    try std.testing.expectEqual(mneme.Metric.cosine, loaded.metric);

    const query = [_]f32{ 1.0, 0.0, 0.0 };
    const results = try loaded.search(&query, 1);
    defer loaded.freeSearchResults(results);
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(std.mem.eql(u8, "doc_1", results[0].id));
}

test "metadata round trip via storage load" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, "source=chat");

    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_metadata.mneme");

    try collection.saveToFile(path);
    var loaded_data = try mneme.storage.loadCollection(path, allocator);
    defer loaded_data.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded_data.points.len);
    try std.testing.expect(loaded_data.points[0].metadata != null);
    try std.testing.expect(std.mem.eql(u8, "source=chat", loaded_data.points[0].metadata.?));
}

test "save and load many points" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const c = [_]f32{ 0.7, 0.3, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, "cat=b");
    try collection.insert("c", &c, null);

    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_many.mneme");

    try collection.saveToFile(path);
    var loaded = try mneme.Collection.loadFromFile(allocator, path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 3), loaded.count());
}

test "delete then save and load preserves state" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();

    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    try collection.insert("a", &a, null);
    try collection.insert("b", &b, null);
    try collection.delete("a");

    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_delete.mneme");

    try collection.saveToFile(path);
    var loaded = try mneme.Collection.loadFromFile(allocator, path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 1), loaded.count());
    const query = [_]f32{ 0.0, 1.0, 0.0 };
    const results = try loaded.search(&query, 1);
    defer loaded.freeSearchResults(results);
    try std.testing.expect(std.mem.eql(u8, "b", results[0].id));
}

test "load wrong magic fails" {
    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_wrong_magic.mneme");

    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = std.c.close(fd);
    const rc = std.c.write(fd, "WRONG".ptr, "WRONG".len);
    try std.testing.expect(rc == "WRONG".len);

    try std.testing.expectError(
        mneme.MnemeError.InvalidMagic,
        mneme.storage.loadCollection(path, std.testing.allocator),
    );
}

test "load truncated file fails" {
    var buf: [256]u8 = undefined;
    const path = try testPath(&buf, "storage_truncated.mneme");

    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = std.c.close(fd);
    const rc = std.c.write(fd, "MNEME".ptr, "MNEME".len);
    try std.testing.expect(rc == "MNEME".len);

    try std.testing.expectError(
        mneme.MnemeError.TruncatedFile,
        mneme.storage.loadCollection(path, std.testing.allocator),
    );
}

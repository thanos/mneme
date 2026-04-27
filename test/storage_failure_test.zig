const std = @import("std");
const mneme = @import("mneme");
const helpers = @import("storage_test_helpers.zig");

fn saveCollectionNoLeak(allocator: std.mem.Allocator) !void {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var collection = try mneme.Collection.init(allocator, "oom_save", 3, .cosine);
    defer collection.deinit();
    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("p1", &v, "m=1");

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_oom_save.mneme");
    defer helpers.deleteFile(path);
    try collection.saveToFile(path);
}

fn loadCollectionNoLeak(allocator: std.mem.Allocator) !void {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &path_buf, "storage_oom_load.mneme");
    defer helpers.deleteFile(path);

    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);
    var writer = mneme.codec.MemoryWriter{
        .allocator = std.testing.allocator,
        .bytes = &bytes,
    };
    try mneme.codec.writeHeader(&writer, .{
        .name = "oom_load",
        .dimension = 3,
        .metric = .cosine,
        .point_count = 1,
    });
    try mneme.codec.writePointRecord(&writer, "p1", "m=1", &[_]f32{ 1.0, 0.0, 0.0 });
    const checksum = std.hash.Crc32.hash(bytes.items);
    try writer.writeInt(u32, checksum, .little);
    try helpers.writeBytes(path, bytes.items);

    var loaded = try mneme.storage.loadCollection(path, allocator);
    defer loaded.deinit();
}

test "save collection handles allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, saveCollectionNoLeak, .{});
}

test "load collection handles allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, loadCollectionNoLeak, .{});
}

test "load wrong magic fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_wrong_magic.mneme");
    defer helpers.deleteFile(path);

    try helpers.writeBytes(path, "WRONG");

    try std.testing.expectError(
        mneme.MnemeError.InvalidMagic,
        mneme.storage.loadCollection(path, std.testing.allocator),
    );
}

test "load truncated file fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_truncated.mneme");
    defer helpers.deleteFile(path);

    try helpers.writeBytes(path, "MNEME");

    try std.testing.expectError(
        mneme.MnemeError.TruncatedFile,
        mneme.storage.loadCollection(path, std.testing.allocator),
    );
}

test "load with trailing bytes fails" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();
    const v = [_]f32{ 1.0, 0.0, 0.0 };
    try collection.insert("doc_1", &v, null);

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_trailing.mneme");
    defer helpers.deleteFile(path);
    try collection.saveToFile(path);

    const bytes = try helpers.readBytes(allocator, path);
    defer allocator.free(bytes);
    const with_trailing = try allocator.alloc(u8, bytes.len + 1);
    defer allocator.free(with_trailing);
    @memcpy(with_trailing[0..bytes.len], bytes);
    with_trailing[bytes.len] = 'x';
    try helpers.writeBytes(path, with_trailing);

    try std.testing.expectError(
        mneme.MnemeError.CorruptRecord,
        mneme.storage.loadCollection(path, allocator),
    );
}

test "load with checksum mismatch fails" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();
    try collection.insert("doc_1", &[_]f32{ 1.0, 0.0, 0.0 }, null);

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_bad_checksum.mneme");
    defer helpers.deleteFile(path);
    try collection.saveToFile(path);

    var bytes = try helpers.readBytes(allocator, path);
    defer allocator.free(bytes);
    bytes[bytes.len - 1] ^= 0xFF;
    try helpers.writeBytes(path, bytes);

    try std.testing.expectError(
        mneme.MnemeError.CorruptRecord,
        mneme.storage.loadCollection(path, allocator),
    );
}

test "truncated checksum footer fails" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();
    try collection.insert("doc_1", &[_]f32{ 1.0, 0.0, 0.0 }, null);

    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "storage_truncated_checksum.mneme");
    defer helpers.deleteFile(path);
    try collection.saveToFile(path);

    var bytes = try helpers.readBytes(allocator, path);
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > 0);
    try helpers.writeBytes(path, bytes[0 .. bytes.len - 1]);

    try std.testing.expectError(
        mneme.MnemeError.TruncatedFile,
        mneme.storage.loadCollection(path, allocator),
    );
}

test "non-existent path fails cleanly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [256]u8 = undefined;
    const path = try helpers.testPath(&tmp, &buf, "does-not-exist.mneme");
    try std.testing.expectError(
        error.FileNotFound,
        mneme.storage.loadCollection(path, std.testing.allocator),
    );
}

test "save rejects path containing nul byte" {
    var ctx: helpers.TestCtx = .{};
    defer ctx.deinit();
    const allocator = ctx.allocator();

    var collection = try mneme.Collection.init(allocator, "docs", 3, .cosine);
    defer collection.deinit();
    try collection.insert("doc_1", &[_]f32{ 1.0, 0.0, 0.0 }, null);

    const bad_path = "bad\x00path.mneme";
    try std.testing.expectError(
        mneme.MnemeError.CorruptRecord,
        collection.saveToFile(bad_path),
    );
}

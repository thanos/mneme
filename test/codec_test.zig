const std = @import("std");
const mneme = @import("mneme");

test "codec round trip header and point record" {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);

    var writer = mneme.codec.MemoryWriter{
        .allocator = std.testing.allocator,
        .bytes = &bytes,
    };

    try mneme.codec.writeHeader(&writer, .{
        .name = "docs",
        .dimension = 3,
        .metric = .cosine,
        .point_count = 1,
    });
    try mneme.codec.writePointRecord(
        &writer,
        "doc_1",
        "source=chat",
        &[_]f32{ 1.0, 2.0, 3.0 },
    );

    var reader = mneme.codec.MemoryReader{ .data = bytes.items };

    const header = try mneme.codec.readHeader(&reader, std.testing.allocator);
    defer std.testing.allocator.free(header.name);

    try std.testing.expect(std.mem.eql(u8, "docs", header.name));
    try std.testing.expectEqual(@as(usize, 3), header.dimension);
    try std.testing.expectEqual(mneme.Metric.cosine, header.metric);
    try std.testing.expectEqual(@as(usize, 1), header.point_count);

    var point = try mneme.codec.readPointRecord(&reader, std.testing.allocator, header.dimension);
    defer point.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.eql(u8, "doc_1", point.id));
    try std.testing.expect(point.metadata != null);
    try std.testing.expect(std.mem.eql(u8, "source=chat", point.metadata.?));
    try std.testing.expectEqual(@as(usize, 3), point.vector.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), point.vector[0], 0.0001);
}

test "wrong magic fails" {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);
    try bytes.appendSlice(std.testing.allocator, "WRONG");

    var reader = mneme.codec.MemoryReader{ .data = bytes.items };
    try std.testing.expectError(
        mneme.MnemeError.InvalidMagic,
        mneme.codec.readHeader(&reader, std.testing.allocator),
    );
}

test "wrong version fails" {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);
    var writer = mneme.codec.MemoryWriter{
        .allocator = std.testing.allocator,
        .bytes = &bytes,
    };

    try writer.writeAll("MNEME");
    try writer.writeInt(u32, 999, .little);
    try writer.writeInt(u32, 3, .little);
    try writer.writeByte(1);
    try writer.writeInt(u32, 4, .little);
    try writer.writeAll("docs");
    try writer.writeInt(u64, 0, .little);

    var reader = mneme.codec.MemoryReader{ .data = bytes.items };
    try std.testing.expectError(
        mneme.MnemeError.UnsupportedVersion,
        mneme.codec.readHeader(&reader, std.testing.allocator),
    );
}

test "truncated file fails" {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);
    try bytes.appendSlice(std.testing.allocator, "MN");

    var reader = mneme.codec.MemoryReader{ .data = bytes.items };
    try std.testing.expectError(
        mneme.MnemeError.TruncatedFile,
        mneme.codec.readHeader(&reader, std.testing.allocator),
    );
}

test "wrong vector length fails" {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.testing.allocator);
    var writer = mneme.codec.MemoryWriter{
        .allocator = std.testing.allocator,
        .bytes = &bytes,
    };

    try mneme.codec.writeHeader(&writer, .{
        .name = "docs",
        .dimension = 3,
        .metric = .cosine,
        .point_count = 1,
    });
    try mneme.codec.writePointRecord(
        &writer,
        "doc_1",
        null,
        &[_]f32{ 1.0, 2.0 },
    );

    var reader = mneme.codec.MemoryReader{ .data = bytes.items };
    const header = try mneme.codec.readHeader(&reader, std.testing.allocator);
    defer std.testing.allocator.free(header.name);

    try std.testing.expectError(
        mneme.MnemeError.VectorLengthMismatch,
        mneme.codec.readPointRecord(&reader, std.testing.allocator, header.dimension),
    );
}

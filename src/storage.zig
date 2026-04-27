const std = @import("std");
const Point = @import("point.zig").Point;
const Metric = @import("index.zig").Metric;
const codec = @import("codec.zig");

pub const LoadedCollectionData = struct {
    name: []u8,
    dimension: usize,
    metric: Metric,
    points: []codec.DecodedPointRecord,

    pub fn deinit(self: *LoadedCollectionData, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.points) |*point| {
            point.deinit(allocator);
        }
        allocator.free(self.points);
    }
};

pub fn saveCollection(
    path: []const u8,
    name: []const u8,
    dimension: usize,
    metric: Metric,
    points: []const Point,
) !void {
    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(std.heap.page_allocator);
    var writer = codec.MemoryWriter{
        .allocator = std.heap.page_allocator,
        .bytes = &bytes,
    };

    try codec.writeHeader(&writer, .{
        .name = name,
        .dimension = dimension,
        .metric = metric,
        .point_count = points.len,
    });
    for (points) |point| {
        try codec.writePointRecord(&writer, point.id, point.metadata, point.vector);
    }
    try writer.flush();

    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = std.c.close(fd);
    try writeAllFd(fd, bytes.items);
}

pub fn loadCollection(path: []const u8, allocator: std.mem.Allocator) !LoadedCollectionData {
    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .RDONLY },
        0,
    );
    defer _ = std.c.close(fd);

    const bytes = try readAllFd(allocator, fd);
    defer allocator.free(bytes);

    var reader = codec.MemoryReader{ .data = bytes };
    const header = try codec.readHeader(&reader, allocator);
    errdefer allocator.free(header.name);

    const points = try allocator.alloc(codec.DecodedPointRecord, header.point_count);
    errdefer allocator.free(points);

    var loaded: usize = 0;
    errdefer {
        var idx: usize = 0;
        while (idx < loaded) : (idx += 1) {
            points[idx].deinit(allocator);
        }
    }

    while (loaded < points.len) : (loaded += 1) {
        points[loaded] = try codec.readPointRecord(&reader, allocator, header.dimension);
    }

    // Any extra bytes are currently tolerated to keep format evolution simple.
    return LoadedCollectionData{
        .name = header.name,
        .dimension = header.dimension,
        .metric = header.metric,
        .points = points,
    };
}

fn writeAllFd(fd: std.posix.fd_t, bytes: []const u8) !void {
    var index: usize = 0;
    while (index < bytes.len) {
        const rc = std.c.write(fd, bytes[index..].ptr, bytes.len - index);
        if (rc < 0) return error.InputOutput;
        const n: usize = @intCast(rc);
        if (n == 0) return error.InputOutput;
        index += n;
    }
}

fn readAllFd(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    var bytes = std.ArrayList(u8).empty;
    errdefer bytes.deinit(allocator);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buf);
        if (n == 0) break;
        try bytes.appendSlice(allocator, buf[0..n]);
    }
    return bytes.toOwnedSlice(allocator);
}

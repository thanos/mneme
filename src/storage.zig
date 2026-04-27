const std = @import("std");
const MnemeError = @import("errors.zig").MnemeError;
const Point = @import("point.zig").Point;
const Metric = @import("index.zig").Metric;
const codec = @import("codec.zig");

pub const LoadedCollectionData = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    dimension: usize,
    metric: Metric,
    points: std.ArrayList(Point),

    pub fn deinit(self: *LoadedCollectionData) void {
        self.allocator.free(self.name);
        for (self.points.items) |*point| {
            point.deinit(self.allocator);
        }
        self.points.deinit(self.allocator);
    }
};

pub const SaveOptions = struct {
    fsync_on_save: bool = true,
};

pub fn saveCollection(
    allocator: std.mem.Allocator,
    path: []const u8,
    name: []const u8,
    dimension: usize,
    metric: Metric,
    points: []const Point,
) !void {
    return saveCollectionWithOptions(allocator, path, name, dimension, metric, points, .{});
}

pub fn saveCollectionWithOptions(
    allocator: std.mem.Allocator,
    path: []const u8,
    name: []const u8,
    dimension: usize,
    metric: Metric,
    points: []const Point,
    options: SaveOptions,
) !void {
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(tmp_path);
    const tmp_path_z = try allocator.dupeSentinel(u8, tmp_path, 0);
    defer allocator.free(tmp_path_z);
    const path_z = try allocator.dupeSentinel(u8, path, 0);
    defer allocator.free(path_z);

    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        tmp_path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = std.c.close(fd);
    errdefer _ = std.c.unlinkat(std.posix.AT.FDCWD, tmp_path_z, 0);

    var writer = FileWriter{ .fd = fd };

    try codec.writeHeader(&writer, .{
        .name = name,
        .dimension = dimension,
        .metric = metric,
        .point_count = points.len,
    });
    for (points) |point| {
        try codec.writePointRecord(&writer, point.id, point.metadata, point.vector);
    }
    const checksum = writer.checksum.final();
    try writer.writeIntRaw(u32, checksum, .little);
    if (options.fsync_on_save and std.c.fsync(fd) != 0) return error.InputOutput;
    if (std.c.renameat(std.posix.AT.FDCWD, tmp_path_z, std.posix.AT.FDCWD, path_z) != 0) {
        return error.InputOutput;
    }
}

pub fn loadCollection(path: []const u8, allocator: std.mem.Allocator) !LoadedCollectionData {
    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .RDONLY },
        0,
    );
    defer _ = std.c.close(fd);
    var reader = FileReader{ .fd = fd };
    const header = try codec.readHeader(&reader, allocator);
    errdefer allocator.free(header.name);

    var points: std.ArrayList(Point) = .empty;
    errdefer {
        for (points.items) |*point| point.deinit(allocator);
        points.deinit(allocator);
    }
    try points.ensureTotalCapacity(allocator, header.point_count);

    var loaded: usize = 0;
    while (loaded < header.point_count) : (loaded += 1) {
        var decoded = try codec.readPointRecord(&reader, allocator, header.dimension);
        points.appendAssumeCapacity(.{
            .id = decoded.id,
            .vector = decoded.vector,
            .metadata = decoded.metadata,
        });
        decoded.id = &.{};
        decoded.vector = &.{};
        decoded.metadata = null;
    }
    const expected_checksum = readIntRawOrMappedError(&reader, u32) catch |err| return err;
    const actual_checksum = reader.checksum.final();
    if (expected_checksum != actual_checksum) return MnemeError.CorruptRecord;
    if (try reader.hasTrailingByte()) return MnemeError.CorruptRecord;

    return LoadedCollectionData{
        .allocator = allocator,
        .name = header.name,
        .dimension = header.dimension,
        .metric = header.metric,
        .points = points,
    };
}

const FileWriter = struct {
    fd: std.posix.fd_t,
    checksum: std.hash.Crc32 = std.hash.Crc32.init(),

    pub fn writeAll(self: *FileWriter, data: []const u8) !void {
        self.checksum.update(data);
        return self.writeAllRaw(data);
    }

    fn writeAllRaw(self: *FileWriter, data: []const u8) !void {
        var index: usize = 0;
        while (index < data.len) {
            const rc = std.c.write(self.fd, data[index..].ptr, data.len - index);
            switch (std.c.errno(rc)) {
                .SUCCESS => {},
                .INTR => continue,
                else => return error.InputOutput,
            }
            const n: usize = @intCast(rc);
            if (n == 0) return error.InputOutput;
            index += n;
        }
    }

    pub fn writeByte(self: *FileWriter, byte: u8) !void {
        var one = [1]u8{byte};
        try self.writeAll(&one);
    }

    pub fn writeInt(self: *FileWriter, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, endian);
        try self.writeAll(&buf);
    }

    fn writeIntRaw(self: *FileWriter, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, endian);
        try self.writeAllRaw(&buf);
    }
};

const FileReader = struct {
    fd: std.posix.fd_t,
    checksum: std.hash.Crc32 = std.hash.Crc32.init(),

    pub fn readNoEof(self: *FileReader, dest: []u8) !void {
        try self.readNoEofRaw(dest);
        self.checksum.update(dest);
    }

    fn readNoEofRaw(self: *FileReader, dest: []u8) !void {
        var index: usize = 0;
        while (index < dest.len) {
            const n = try std.posix.read(self.fd, dest[index..]);
            if (n == 0) return error.EndOfStream;
            index += n;
        }
    }

    pub fn readByte(self: *FileReader) !u8 {
        var one: [1]u8 = undefined;
        try self.readNoEof(&one);
        return one[0];
    }

    pub fn readInt(self: *FileReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf: [@sizeOf(T)]u8 = undefined;
        try self.readNoEof(&buf);
        return std.mem.readInt(T, &buf, endian);
    }

    fn readIntRaw(self: *FileReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf: [@sizeOf(T)]u8 = undefined;
        try self.readNoEofRaw(&buf);
        return std.mem.readInt(T, &buf, endian);
    }

    pub fn hasTrailingByte(self: *FileReader) !bool {
        var one: [1]u8 = undefined;
        const n = try std.posix.read(self.fd, &one);
        return n > 0;
    }
};

fn readIntRawOrMappedError(reader: *FileReader, comptime T: type) MnemeError!T {
    return reader.readIntRaw(T, .little) catch |err| switch (err) {
        error.EndOfStream => MnemeError.TruncatedFile,
        else => MnemeError.CorruptRecord,
    };
}

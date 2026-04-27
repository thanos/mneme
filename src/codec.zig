const std = @import("std");
const Metric = @import("index.zig").Metric;
const MnemeError = @import("errors.zig").MnemeError;

pub const format_version: u32 = 2;
const magic = "MNEME";
const null_metadata_len = std.math.maxInt(u32);

pub const FileHeader = struct {
    name: []const u8,
    dimension: usize,
    metric: Metric,
    point_count: usize,
};

pub const DecodedHeader = struct {
    name: []u8,
    dimension: usize,
    metric: Metric,
    point_count: usize,
};

pub const DecodedPointRecord = struct {
    id: []u8,
    metadata: ?[]u8,
    vector: []f32,

    pub fn deinit(self: *DecodedPointRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.metadata) |metadata| allocator.free(metadata);
        allocator.free(self.vector);
    }
};

pub const MemoryWriter = struct {
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),

    pub fn writeAll(self: *MemoryWriter, data: []const u8) !void {
        try self.bytes.appendSlice(self.allocator, data);
    }

    pub fn writeByte(self: *MemoryWriter, byte: u8) !void {
        try self.bytes.append(self.allocator, byte);
    }

    pub fn writeInt(self: *MemoryWriter, comptime T: type, value: T, endian: std.builtin.Endian) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, endian);
        try self.writeAll(&buf);
    }

    pub fn flush(_: *MemoryWriter) !void {}
};

pub const MemoryReader = struct {
    data: []const u8,
    index: usize = 0,

    pub fn readNoEof(self: *MemoryReader, dest: []u8) !void {
        if (self.index > self.data.len) return error.EndOfStream;
        if (dest.len > self.data.len - self.index) return error.EndOfStream;
        @memcpy(dest, self.data[self.index .. self.index + dest.len]);
        self.index += dest.len;
    }

    pub fn readByte(self: *MemoryReader) !u8 {
        if (self.index >= self.data.len) return error.EndOfStream;
        const byte = self.data[self.index];
        self.index += 1;
        return byte;
    }

    pub fn readInt(self: *MemoryReader, comptime T: type, endian: std.builtin.Endian) !T {
        var buf: [@sizeOf(T)]u8 = undefined;
        try self.readNoEof(&buf);
        return std.mem.readInt(T, &buf, endian);
    }
};

pub fn writeHeader(writer: anytype, header: FileHeader) !void {
    try writer.writeAll(magic);
    try writer.writeInt(u32, format_version, .little);
    const dim = std.math.cast(u32, header.dimension) orelse return MnemeError.InvalidDimension;
    try writer.writeInt(u32, dim, .little);
    try writer.writeByte(metricToByte(header.metric));
    const name_len = std.math.cast(u32, header.name.len) orelse return MnemeError.CorruptRecord;
    try writer.writeInt(u32, name_len, .little);
    try writer.writeAll(header.name);
    const point_count = std.math.cast(u64, header.point_count) orelse return MnemeError.CorruptRecord;
    try writer.writeInt(u64, point_count, .little);
}

pub fn writePointRecord(
    writer: anytype,
    id: []const u8,
    metadata: ?[]const u8,
    vector: []const f32,
) !void {
    const id_len = std.math.cast(u32, id.len) orelse return MnemeError.CorruptRecord;
    try writer.writeInt(u32, id_len, .little);
    try writer.writeAll(id);

    if (metadata) |value| {
        const metadata_len = std.math.cast(u32, value.len) orelse return MnemeError.CorruptRecord;
        try writer.writeInt(u32, metadata_len, .little);
        try writer.writeAll(value);
    } else {
        try writer.writeInt(u32, null_metadata_len, .little);
    }

    const vector_len = std.math.cast(u32, vector.len) orelse return MnemeError.CorruptRecord;
    try writer.writeInt(u32, vector_len, .little);
    if (@import("builtin").cpu.arch.endian() == .little) {
        try writer.writeAll(std.mem.sliceAsBytes(vector));
    } else {
        for (vector) |value| {
            try writer.writeInt(u32, @as(u32, @bitCast(value)), .little);
        }
    }
}

pub fn readHeader(reader: anytype, allocator: std.mem.Allocator) !DecodedHeader {
    var header = DecodedHeader{
        .name = &.{},
        .dimension = 0,
        .metric = .cosine,
        .point_count = 0,
    };
    errdefer allocator.free(header.name);

    var magic_buf: [magic.len]u8 = undefined;
    readAllOrTruncated(reader, &magic_buf) catch return MnemeError.TruncatedFile;
    if (!std.mem.eql(u8, &magic_buf, magic)) return MnemeError.InvalidMagic;

    const version = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    if (version != format_version) return MnemeError.UnsupportedVersion;

    const dimension = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    if (dimension == 0) return MnemeError.InvalidDimension;
    header.dimension = dimension;

    const metric_byte = reader.readByte() catch |err| return mapReadError(err);
    header.metric = byteToMetric(metric_byte) orelse return MnemeError.InvalidMetric;

    const name_len = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    header.name = try allocator.alloc(u8, name_len);
    readAllOrTruncated(reader, header.name) catch return MnemeError.TruncatedFile;

    const point_count = readIntOrTruncated(reader, u64) catch return MnemeError.TruncatedFile;
    header.point_count = std.math.cast(usize, point_count) orelse return MnemeError.CorruptRecord;
    return header;
}

pub fn readPointRecord(
    reader: anytype,
    allocator: std.mem.Allocator,
    expected_dimension: usize,
) !DecodedPointRecord {
    var record = DecodedPointRecord{
        .id = &.{},
        .metadata = null,
        .vector = &.{},
    };
    errdefer {
        if (record.id.len > 0) allocator.free(record.id);
        if (record.metadata) |metadata| allocator.free(metadata);
        if (record.vector.len > 0) allocator.free(record.vector);
    }

    const id_len = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    record.id = try allocator.alloc(u8, id_len);
    readAllOrTruncated(reader, record.id) catch return MnemeError.TruncatedFile;

    const metadata_len = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    if (metadata_len != null_metadata_len) {
        const metadata = try allocator.alloc(u8, metadata_len);
        record.metadata = metadata;
        readAllOrTruncated(reader, metadata) catch return MnemeError.TruncatedFile;
    }

    const vector_len = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
    if (vector_len != expected_dimension) return MnemeError.VectorLengthMismatch;

    record.vector = try allocator.alloc(f32, vector_len);
    if (@import("builtin").cpu.arch.endian() == .little) {
        readAllOrTruncated(reader, std.mem.sliceAsBytes(record.vector)) catch return MnemeError.TruncatedFile;
    } else {
        for (record.vector) |*value| {
            const bits = readIntOrTruncated(reader, u32) catch return MnemeError.TruncatedFile;
            value.* = @as(f32, @bitCast(bits));
        }
    }
    return record;
}

fn metricToByte(metric: Metric) u8 {
    return switch (metric) {
        .cosine => 1,
    };
}

fn byteToMetric(value: u8) ?Metric {
    return switch (value) {
        1 => .cosine,
        else => null,
    };
}

fn readIntOrTruncated(reader: anytype, comptime T: type) MnemeError!T {
    return reader.readInt(T, .little) catch |err| return mapReadError(err);
}

fn readAllOrTruncated(reader: anytype, dest: []u8) MnemeError!void {
    reader.readNoEof(dest) catch |err| return mapReadError(err);
}

fn mapReadError(err: anyerror) MnemeError {
    return switch (err) {
        error.EndOfStream => MnemeError.TruncatedFile,
        else => MnemeError.CorruptRecord,
    };
}

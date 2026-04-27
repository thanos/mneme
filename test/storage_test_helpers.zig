const std = @import("std");
const mneme = @import("mneme");

pub const TestCtx = struct {
    gpa: std.heap.DebugAllocator(.{}) = .init,

    pub fn allocator(self: *TestCtx) std.mem.Allocator {
        return self.gpa.allocator();
    }

    pub fn deinit(self: *TestCtx) void {
        std.debug.assert(self.gpa.deinit() == .ok);
    }
};

pub fn testPath(tmp: *std.testing.TmpDir, buf: *[256]u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path, name });
}

pub fn writeBytes(path: []const u8, bytes: []const u8) !void {
    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = closeFd(fd);

    var index: usize = 0;
    while (index < bytes.len) {
        const rc = std.posix.system.write(fd, bytes[index..].ptr, bytes.len - index);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return error.InputOutput,
        }
        try std.testing.expect(rc > 0);
        index += @intCast(rc);
    }
}

pub fn readBytes(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .RDONLY },
        0,
    );
    defer _ = closeFd(fd);

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

pub fn deleteFile(path: []const u8) void {
    if (std.mem.findScalar(u8, path, 0) != null) return;
    var buf: [256]u8 = undefined;
    if (path.len + 1 > buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = std.posix.system.unlinkat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0].ptr), 0);
}

pub fn saveLoadCollection(
    allocator: std.mem.Allocator,
    collection: *mneme.Collection,
    path: []const u8,
) !mneme.Collection {
    try collection.saveToFile(path);
    return mneme.Collection.loadFromFile(allocator, path);
}

pub fn saveLoadRaw(path: []const u8, allocator: std.mem.Allocator) !mneme.storage.LoadedCollectionData {
    return mneme.storage.loadCollection(path, allocator);
}

fn closeFd(fd: std.posix.fd_t) void {
    _ = std.posix.system.close(fd);
}

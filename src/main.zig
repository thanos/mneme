const std = @import("std");
const mneme = @import("mneme");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    var collection = try mneme.Collection.init(allocator, "benchmark", 384, .cosine);
    defer collection.deinit();

    const total_vectors = 10_000;
    const dimension = 384;

    var start_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&start_tv, null);

    var i: usize = 0;
    while (i < total_vectors) : (i += 1) {
        const buffer = try allocator.alloc(f32, dimension);
        defer allocator.free(buffer);

        for (buffer, 0..) |*value, j| {
            value.* = @as(f32, @floatFromInt((i + j) % 17)) / 17.0;
        }

        var id_buf: [32]u8 = undefined;
        const id = try std.fmt.bufPrint(&id_buf, "v_{d}", .{i});
        try collection.insert(id, buffer, null);
    }

    const query = try allocator.alloc(f32, dimension);
    defer allocator.free(query);
    for (query, 0..) |*value, j| {
        value.* = @as(f32, @floatFromInt(j % 11)) / 11.0;
    }

    const results = try collection.search(query, 10);
    defer collection.freeSearchResults(results);

    var end_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&end_tv, null);
    const start_us: i128 = @as(i128, start_tv.sec) * 1_000_000 + @as(i128, start_tv.usec);
    const end_us: i128 = @as(i128, end_tv.sec) * 1_000_000 + @as(i128, end_tv.usec);
    const elapsed_ms = @as(f64, @floatFromInt(end_us - start_us)) / 1_000.0;

    std.debug.print(
        "Inserted {d} vectors of dimension {d}, searched top {d}, elapsed: {d:.3} ms\n",
        .{ total_vectors, dimension, results.len, elapsed_ms },
    );
}

const std = @import("std");
const mneme = @import("mneme");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("memory leak detected");
    }
    const allocator = gpa.allocator();

    const total_vectors = 10_000;
    const dimension = 384;
    const path = ".zig-cache/benchmark.mneme";

    var collection = try mneme.Collection.init(allocator, "benchmark", dimension, .cosine);
    defer collection.deinit();

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

    var insert_done_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&insert_done_tv, null);

    try collection.saveToFileWithOptions(path, .{ .fsync_on_save = false });
    var save_done_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&save_done_tv, null);

    var loaded = try mneme.Collection.loadFromFile(allocator, path);
    defer loaded.deinit();

    var load_done_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&load_done_tv, null);

    const query = try allocator.alloc(f32, dimension);
    defer allocator.free(query);
    for (query, 0..) |*value, j| {
        value.* = @as(f32, @floatFromInt(j % 11)) / 11.0;
    }

    const results = try loaded.search(query, 10);
    defer loaded.freeSearchResults(results);

    var end_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&end_tv, null);
    const insert_ms = deltaMs(start_tv, insert_done_tv);
    const save_ms = deltaMs(insert_done_tv, save_done_tv);
    const load_ms = deltaMs(save_done_tv, load_done_tv);
    const search_ms = deltaMs(load_done_tv, end_tv);

    std.debug.print(
        "insert: {d:.3} ms | save: {d:.3} ms | load: {d:.3} ms | search(top {d}): {d:.3} ms\n",
        .{ insert_ms, save_ms, load_ms, results.len, search_ms },
    );
}

fn deltaMs(start_tv: std.c.timeval, end_tv: std.c.timeval) f64 {
    const start_us: i128 = @as(i128, start_tv.sec) * 1_000_000 + @as(i128, start_tv.usec);
    const end_us: i128 = @as(i128, end_tv.sec) * 1_000_000 + @as(i128, end_tv.usec);
    const elapsed_ms = @as(f64, @floatFromInt(end_us - start_us)) / 1_000.0;
    if (elapsed_ms > 60_000.0) {
        std.debug.print(
            "warning: benchmark stage took {d:.3} ms (> 60000 ms soft threshold)\n",
            .{elapsed_ms},
        );
    }
    return elapsed_ms;
}

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
    var flat_done_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&flat_done_tv, null);

    try loaded.buildHnsw(.{
        .m = 16,
        .ef_construction = 128,
        .ef_search = 64,
        .seed = 42,
    });
    var hnsw_build_done_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&hnsw_build_done_tv, null);

    const ann_results = try loaded.searchWithOptions(query, 10, .{
        .index = .hnsw,
        .ef_search = 64,
    });
    defer loaded.freeSearchResults(ann_results);

    var end_tv: std.c.timeval = undefined;
    _ = std.c.gettimeofday(&end_tv, null);
    const insert_ms = deltaMs(start_tv, insert_done_tv);
    const save_ms = deltaMs(insert_done_tv, save_done_tv);
    const load_ms = deltaMs(save_done_tv, load_done_tv);
    const flat_search_ms = deltaMs(load_done_tv, flat_done_tv);
    const hnsw_build_ms = deltaMs(flat_done_tv, hnsw_build_done_tv);
    const hnsw_search_ms = deltaMs(hnsw_build_done_tv, end_tv);
    const overlap = overlapCount(results, ann_results);

    std.debug.print(
        "insert: {d:.3} ms | save: {d:.3} ms | load: {d:.3} ms | flat(top {d}): {d:.3} ms | hnsw build: {d:.3} ms | hnsw(top {d}): {d:.3} ms | overlap: {d}/{d}\n",
        .{
            insert_ms,
            save_ms,
            load_ms,
            results.len,
            flat_search_ms,
            hnsw_build_ms,
            ann_results.len,
            hnsw_search_ms,
            overlap,
            results.len,
        },
    );
}

fn overlapCount(flat: []const mneme.SearchResult, ann: []const mneme.SearchResult) usize {
    var overlap: usize = 0;
    for (ann) |a| {
        for (flat) |f| {
            if (std.mem.eql(u8, a.id, f.id)) {
                overlap += 1;
                break;
            }
        }
    }
    return overlap;
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

const std = @import("std");
const Point = @import("point.zig").Point;
const cosineSimilarity = @import("distance.zig").cosineSimilarity;
const MnemeError = @import("errors.zig").MnemeError;

pub const Metric = enum {
    cosine,
};

pub const SearchResult = struct {
    id: []const u8,
    score: f32,
};

pub const FlatIndex = struct {
    pub fn search(
        allocator: std.mem.Allocator,
        points: []const Point,
        query_vector: []const f32,
        top_k: usize,
        metric: Metric,
    ) ![]SearchResult {
        if (query_vector.len == 0) return MnemeError.EmptyVector;
        if (top_k == 0 or points.len == 0) {
            return allocator.alloc(SearchResult, 0);
        }

        var scored: std.ArrayList(SearchResult) = .empty;
        defer scored.deinit(allocator);

        for (points) |point| {
            const score = switch (metric) {
                .cosine => try cosineSimilarity(point.vector, query_vector),
            };
            try scored.append(allocator, .{
                .id = point.id,
                .score = score,
            });
        }

        std.mem.sort(SearchResult, scored.items, {}, lessThanByScoreDesc);

        const n = @min(top_k, scored.items.len);
        const results = try allocator.alloc(SearchResult, n);
        @memcpy(results, scored.items[0..n]);
        return results;
    }

    fn lessThanByScoreDesc(_: void, left: SearchResult, right: SearchResult) bool {
        return left.score > right.score;
    }
};

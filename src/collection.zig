const std = @import("std");
const Point = @import("point.zig").Point;
const FlatIndex = @import("index.zig").FlatIndex;
const SearchResult = @import("index.zig").SearchResult;
const Metric = @import("index.zig").Metric;
const MnemeError = @import("errors.zig").MnemeError;
const vector = @import("vector.zig");
const storage = @import("storage.zig");

pub const Collection = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    dimension: usize,
    metric: Metric,
    points: std.ArrayList(Point),

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        dimension: usize,
        metric: Metric,
    ) !Collection {
        if (dimension == 0) return MnemeError.InvalidDimension;

        return Collection{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .dimension = dimension,
            .metric = metric,
            .points = .empty,
        };
    }

    pub fn deinit(self: *Collection) void {
        for (self.points.items) |*point| {
            point.deinit(self.allocator);
        }
        self.points.deinit(self.allocator);
        self.allocator.free(self.name);
    }

    pub fn insert(
        self: *Collection,
        id: []const u8,
        input_vector: []const f32,
        metadata: ?[]const u8,
    ) !void {
        try vector.ensureDimension(input_vector, self.dimension);

        if (self.findPointIndex(id) != null) return MnemeError.DuplicateId;

        var point = try Point.init(self.allocator, id, input_vector, metadata);
        errdefer point.deinit(self.allocator);
        try self.points.append(self.allocator, point);
    }

    pub fn delete(self: *Collection, id: []const u8) !void {
        const idx = self.findPointIndex(id) orelse return MnemeError.IdNotFound;

        var removed = self.points.swapRemove(idx);
        removed.deinit(self.allocator);
    }

    pub fn count(self: *const Collection) usize {
        return self.points.items.len;
    }

    pub fn search(self: *const Collection, query_vector: []const f32, top_k: usize) ![]SearchResult {
        try vector.ensureDimension(query_vector, self.dimension);
        return FlatIndex.search(self.allocator, self.points.items, query_vector, top_k, self.metric);
    }

    pub fn freeSearchResults(self: *const Collection, results: []SearchResult) void {
        FlatIndex.freeSearchResults(self.allocator, results);
    }

    pub fn saveToFile(self: *const Collection, path: []const u8) !void {
        try storage.saveCollection(path, self.name, self.dimension, self.metric, self.points.items);
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Collection {
        var loaded = try storage.loadCollection(path, allocator);
        defer loaded.deinit(allocator);

        var collection = try Collection.init(allocator, loaded.name, loaded.dimension, loaded.metric);
        errdefer collection.deinit();

        for (loaded.points) |point| {
            try collection.insert(point.id, point.vector, point.metadata);
        }
        return collection;
    }

    fn findPointIndex(self: *const Collection, id: []const u8) ?usize {
        for (self.points.items, 0..) |point, idx| {
            if (std.mem.eql(u8, point.id, id)) return idx;
        }
        return null;
    }
};

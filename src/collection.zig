const std = @import("std");
const Point = @import("point.zig").Point;
const FlatIndex = @import("index.zig").FlatIndex;
const SearchResult = @import("index.zig").SearchResult;
const Metric = @import("index.zig").Metric;
const SearchOptions = @import("index.zig").SearchOptions;
const HnswIndex = @import("hnsw.zig").HnswIndex;
const HnswConfig = @import("hnsw.zig").HnswConfig;
const MnemeError = @import("errors.zig").MnemeError;
const vector = @import("vector.zig");
const storage = @import("storage.zig");

pub const Collection = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    dimension: usize,
    metric: Metric,
    points: std.ArrayList(Point),
    hnsw_index: ?HnswIndex,
    hnsw_stale: bool,

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
            .hnsw_index = null,
            .hnsw_stale = false,
        };
    }

    pub fn deinit(self: *Collection) void {
        if (self.hnsw_index) |*index| {
            index.deinit();
        }
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
        self.markHnswStale();
    }

    pub fn delete(self: *Collection, id: []const u8) !void {
        const idx = self.findPointIndex(id) orelse return MnemeError.IdNotFound;

        var removed = self.points.swapRemove(idx);
        removed.deinit(self.allocator);
        self.markHnswStale();
    }

    pub fn count(self: *const Collection) usize {
        return self.points.items.len;
    }

    pub fn search(self: *const Collection, query_vector: []const f32, top_k: usize) ![]SearchResult {
        try vector.ensureDimension(query_vector, self.dimension);
        return FlatIndex.search(self.allocator, self.points.items, query_vector, top_k, self.metric);
    }

    pub fn searchWithOptions(
        self: *const Collection,
        query_vector: []const f32,
        top_k: usize,
        options: SearchOptions,
    ) ![]SearchResult {
        return switch (options.index) {
            .flat => self.search(query_vector, top_k),
            .hnsw => blk: {
                if (self.hnsw_stale) return MnemeError.IndexStale;
                if (self.hnsw_index) |*index| {
                    break :blk index.search(self.points.items, query_vector, top_k, options.ef_search);
                }
                return MnemeError.IndexNotBuilt;
            },
        };
    }

    pub fn buildHnsw(self: *Collection, config: HnswConfig) !void {
        if (self.hnsw_index) |*index| {
            index.deinit();
            self.hnsw_index = null;
        }
        var index = try HnswIndex.init(self.allocator, self.dimension, self.metric, config);
        errdefer index.deinit();
        try index.build(self.points.items);
        self.hnsw_index = index;
        self.hnsw_stale = false;
    }

    pub fn freeSearchResults(self: *const Collection, results: []SearchResult) void {
        FlatIndex.freeSearchResults(self.allocator, results);
    }

    pub fn saveToFile(self: *const Collection, path: []const u8) !void {
        try storage.saveCollection(self.allocator, path, self.name, self.dimension, self.metric, self.points.items);
    }

    pub fn saveToFileWithOptions(
        self: *const Collection,
        path: []const u8,
        options: storage.SaveOptions,
    ) !void {
        try storage.saveCollectionWithOptions(
            self.allocator,
            path,
            self.name,
            self.dimension,
            self.metric,
            self.points.items,
            options,
        );
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Collection {
        var loaded = try storage.loadCollection(path, allocator);
        errdefer loaded.deinit();

        const collection = Collection{
            .allocator = allocator,
            .name = loaded.name,
            .dimension = loaded.dimension,
            .metric = loaded.metric,
            .points = loaded.points,
            .hnsw_index = null,
            .hnsw_stale = false,
        };
        loaded.name = &.{};
        loaded.points = .empty;
        return collection;
    }

    fn findPointIndex(self: *const Collection, id: []const u8) ?usize {
        for (self.points.items, 0..) |point, idx| {
            if (std.mem.eql(u8, point.id, id)) return idx;
        }
        return null;
    }

    fn markHnswStale(self: *Collection) void {
        if (self.hnsw_index != null) {
            self.hnsw_stale = true;
        }
    }
};

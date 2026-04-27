const std = @import("std");
const Point = @import("point.zig").Point;
const SearchResult = @import("index.zig").SearchResult;
const Metric = @import("index.zig").Metric;
const cosineSimilarity = @import("distance.zig").cosineSimilarity;
const MnemeError = @import("errors.zig").MnemeError;
const vector = @import("vector.zig");

pub const HnswConfig = struct {
    m: usize = 16,
    ef_construction: usize = 64,
    ef_search: usize = 32,
    seed: u64 = 42,
};

const ScoredNode = struct {
    node_index: usize,
    score: f32,
};

pub const HnswNode = struct {
    point_index: usize,
    level: usize,
    neighbors_by_layer: []std.ArrayList(usize),

    fn deinit(self: *HnswNode, allocator: std.mem.Allocator) void {
        for (self.neighbors_by_layer) |*neighbors| {
            neighbors.deinit(allocator);
        }
        allocator.free(self.neighbors_by_layer);
    }
};

pub const HnswIndex = struct {
    allocator: std.mem.Allocator,
    dimension: usize,
    metric: Metric,
    config: HnswConfig,
    nodes: std.ArrayList(HnswNode),
    entry_point: ?usize,
    max_level: isize,
    prng: std.Random.DefaultPrng,

    pub fn init(
        allocator: std.mem.Allocator,
        dimension: usize,
        metric: Metric,
        config: HnswConfig,
    ) !HnswIndex {
        try validateConfig(config);
        if (dimension == 0) return MnemeError.InvalidDimension;
        switch (metric) {
            .cosine => {},
        }
        return .{
            .allocator = allocator,
            .dimension = dimension,
            .metric = metric,
            .config = config,
            .nodes = .empty,
            .entry_point = null,
            .max_level = -1,
            .prng = std.Random.DefaultPrng.init(config.seed),
        };
    }

    pub fn deinit(self: *HnswIndex) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.entry_point = null;
        self.max_level = -1;
    }

    pub fn build(self: *HnswIndex, points: []const Point) !void {
        self.clearGraph();
        for (points, 0..) |point, point_index| {
            try vector.ensureDimension(point.vector, self.dimension);
            try self.insert(points, point_index, point.vector);
        }
    }

    pub fn insert(self: *HnswIndex, points: []const Point, point_index: usize, point_vector: []const f32) !void {
        try vector.ensureDimension(point_vector, self.dimension);
        const level = self.randomLevel();
        const node_index = try self.addNode(point_index, level);

        if (self.entry_point == null) {
            self.entry_point = node_index;
            self.max_level = @as(isize, @intCast(level));
            return;
        }

        var current = self.entry_point.?;
        var layer: isize = self.max_level;
        while (layer > @as(isize, @intCast(level))) : (layer -= 1) {
            current = try self.greedySearchAtLayer(points, point_vector, current, @as(usize, @intCast(layer)));
        }

        const connect_max_layer = @min(@as(usize, @intCast(self.max_level)), level);
        var l: isize = @as(isize, @intCast(connect_max_layer));
        while (l >= 0) : (l -= 1) {
            const layer_usize: usize = @intCast(l);
            var candidates = try self.searchLayer(
                points,
                point_vector,
                current,
                self.config.ef_construction,
                layer_usize,
            );
            defer candidates.deinit(self.allocator);

            std.mem.sort(ScoredNode, candidates.items, {}, lessThanByScoreDesc);
            const neighbor_count = @min(self.config.m, candidates.items.len);
            for (candidates.items[0..neighbor_count]) |candidate| {
                try self.connectBidirectional(points, node_index, candidate.node_index, layer_usize);
            }
            if (candidates.items.len > 0) {
                current = candidates.items[0].node_index;
            }
        }

        if (@as(isize, @intCast(level)) > self.max_level) {
            self.entry_point = node_index;
            self.max_level = @as(isize, @intCast(level));
        }
    }

    pub fn search(
        self: *const HnswIndex,
        points: []const Point,
        query: []const f32,
        top_k: usize,
        ef_search: ?usize,
    ) ![]SearchResult {
        try vector.ensureDimension(query, self.dimension);
        if (top_k == 0 or self.nodes.items.len == 0) {
            return self.allocator.alloc(SearchResult, 0);
        }

        const ef = if (ef_search) |value| blk: {
            if (value == 0) return MnemeError.InvalidEfSearch;
            break :blk @max(value, top_k);
        } else @max(self.config.ef_search, top_k);

        var current = self.entry_point.?;
        var layer = self.max_level;
        while (layer > 0) : (layer -= 1) {
            current = try self.greedySearchAtLayer(points, query, current, @as(usize, @intCast(layer)));
        }

        var candidates = try self.searchLayer(points, query, current, ef, 0);
        defer candidates.deinit(self.allocator);
        std.mem.sort(ScoredNode, candidates.items, {}, lessThanByScoreDesc);

        const result_count = @min(top_k, candidates.items.len);
        const results = try self.allocator.alloc(SearchResult, result_count);
        var initialized: usize = 0;
        errdefer {
            var idx: usize = 0;
            while (idx < initialized) : (idx += 1) {
                self.allocator.free(results[idx].id);
            }
            self.allocator.free(results);
        }

        var idx: usize = 0;
        while (idx < result_count) : (idx += 1) {
            const point = points[self.nodes.items[candidates.items[idx].node_index].point_index];
            results[idx] = .{
                .id = try self.allocator.dupe(u8, point.id),
                .score = candidates.items[idx].score,
            };
            initialized += 1;
        }
        return results;
    }

    fn clearGraph(self: *HnswIndex) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.clearRetainingCapacity();
        self.entry_point = null;
        self.max_level = -1;
        self.prng = std.Random.DefaultPrng.init(self.config.seed);
    }

    fn randomLevel(self: *HnswIndex) usize {
        var level: usize = 0;
        var rng = self.prng.random();
        while (rng.float(f32) < 0.5 and level < 32) {
            level += 1;
        }
        return level;
    }

    fn addNode(self: *HnswIndex, point_index: usize, level: usize) !usize {
        const neighbors_by_layer = try self.allocator.alloc(std.ArrayList(usize), level + 1);
        var initialized: usize = 0;
        errdefer {
            var idx: usize = 0;
            while (idx < initialized) : (idx += 1) {
                neighbors_by_layer[idx].deinit(self.allocator);
            }
            self.allocator.free(neighbors_by_layer);
        }

        var layer_idx: usize = 0;
        while (layer_idx <= level) : (layer_idx += 1) {
            neighbors_by_layer[layer_idx] = .empty;
            initialized += 1;
        }

        try self.nodes.append(self.allocator, .{
            .point_index = point_index,
            .level = level,
            .neighbors_by_layer = neighbors_by_layer,
        });
        return self.nodes.items.len - 1;
    }

    fn greedySearchAtLayer(
        self: *const HnswIndex,
        points: []const Point,
        query: []const f32,
        start_node: usize,
        layer: usize,
    ) !usize {
        var current = start_node;
        var current_score = try self.similarity(points, current, query);
        var improved = true;
        while (improved) {
            improved = false;
            for (self.nodes.items[current].neighbors_by_layer[layer].items) |neighbor| {
                const neighbor_score = try self.similarity(points, neighbor, query);
                if (neighbor_score > current_score) {
                    current = neighbor;
                    current_score = neighbor_score;
                    improved = true;
                }
            }
        }
        return current;
    }

    fn searchLayer(
        self: *const HnswIndex,
        points: []const Point,
        query: []const f32,
        entry_node: usize,
        ef: usize,
        layer: usize,
    ) !std.ArrayList(ScoredNode) {
        var visited = try self.allocator.alloc(bool, self.nodes.items.len);
        defer self.allocator.free(visited);
        @memset(visited, false);

        var candidates: std.ArrayList(ScoredNode) = .empty;
        defer candidates.deinit(self.allocator);
        var results: std.ArrayList(ScoredNode) = .empty;
        errdefer results.deinit(self.allocator);

        const entry_score = try self.similarity(points, entry_node, query);
        try candidates.append(self.allocator, .{ .node_index = entry_node, .score = entry_score });
        try results.append(self.allocator, .{ .node_index = entry_node, .score = entry_score });
        visited[entry_node] = true;

        while (candidates.items.len > 0) {
            const best_idx = bestCandidateIndex(candidates.items);
            const candidate = candidates.swapRemove(best_idx);
            const worst_idx = worstResultIndex(results.items);
            const worst_score = results.items[worst_idx].score;
            if (results.items.len >= ef and candidate.score < worst_score) break;

            for (self.nodes.items[candidate.node_index].neighbors_by_layer[layer].items) |neighbor| {
                if (visited[neighbor]) continue;
                visited[neighbor] = true;

                const score = try self.similarity(points, neighbor, query);
                if (results.items.len < ef or score > results.items[worstResultIndex(results.items)].score) {
                    try candidates.append(self.allocator, .{ .node_index = neighbor, .score = score });
                    try results.append(self.allocator, .{ .node_index = neighbor, .score = score });
                    if (results.items.len > ef) {
                        _ = results.swapRemove(worstResultIndex(results.items));
                    }
                }
            }
        }

        return results;
    }

    fn connectBidirectional(
        self: *HnswIndex,
        points: []const Point,
        a: usize,
        b: usize,
        layer: usize,
    ) !void {
        try self.addUniqueNeighbor(a, layer, b);
        try self.addUniqueNeighbor(b, layer, a);
        try self.pruneLayer(points, a, layer);
        try self.pruneLayer(points, b, layer);
    }

    fn addUniqueNeighbor(self: *HnswIndex, node_index: usize, layer: usize, neighbor: usize) !void {
        const list = &self.nodes.items[node_index].neighbors_by_layer[layer];
        for (list.items) |existing| {
            if (existing == neighbor) return;
        }
        try list.append(self.allocator, neighbor);
    }

    fn pruneLayer(self: *HnswIndex, points: []const Point, node_index: usize, layer: usize) !void {
        const list = &self.nodes.items[node_index].neighbors_by_layer[layer];
        if (list.items.len <= self.config.m) return;

        const query_vector = points[self.nodes.items[node_index].point_index].vector;
        var scored: std.ArrayList(ScoredNode) = .empty;
        defer scored.deinit(self.allocator);
        for (list.items) |neighbor| {
            const score = try self.similarity(points, neighbor, query_vector);
            try scored.append(self.allocator, .{ .node_index = neighbor, .score = score });
        }
        std.mem.sort(ScoredNode, scored.items, {}, lessThanByScoreDesc);
        list.clearRetainingCapacity();
        const keep = @min(self.config.m, scored.items.len);
        for (scored.items[0..keep]) |item| {
            try list.append(self.allocator, item.node_index);
        }
    }

    fn similarity(self: *const HnswIndex, points: []const Point, node_index: usize, query: []const f32) !f32 {
        const point = points[self.nodes.items[node_index].point_index];
        return switch (self.metric) {
            .cosine => cosineSimilarity(point.vector, query),
        };
    }
};

fn validateConfig(config: HnswConfig) MnemeError!void {
    if (config.m == 0) return MnemeError.InvalidIndexConfig;
    if (config.ef_construction < config.m) return MnemeError.InvalidIndexConfig;
    if (config.ef_search == 0) return MnemeError.InvalidIndexConfig;
}

fn lessThanByScoreDesc(_: void, left: ScoredNode, right: ScoredNode) bool {
    return left.score > right.score;
}

fn bestCandidateIndex(candidates: []const ScoredNode) usize {
    var best_idx: usize = 0;
    var i: usize = 1;
    while (i < candidates.len) : (i += 1) {
        if (candidates[i].score > candidates[best_idx].score) best_idx = i;
    }
    return best_idx;
}

fn worstResultIndex(results: []const ScoredNode) usize {
    var worst_idx: usize = 0;
    var i: usize = 1;
    while (i < results.len) : (i += 1) {
        if (results[i].score < results[worst_idx].score) worst_idx = i;
    }
    return worst_idx;
}

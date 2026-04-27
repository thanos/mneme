const std = @import("std");
const Point = @import("point.zig").Point;
const SearchResult = @import("index.zig").SearchResult;
const Metric = @import("index.zig").Metric;
const MnemeError = @import("errors.zig").MnemeError;
const vector = @import("vector.zig");

pub const HnswConfig = struct {
    m: usize = 16,
    ef_construction: usize = 64,
    ef_search: usize = 32,
    seed: u64 = 42,
};

pub const HnswStats = struct {
    node_count: usize,
    max_level: isize,
    avg_degree_layer0: f64,
    level_counts: []usize,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *HnswStats) void {
        self.allocator.free(self.level_counts);
        self.level_counts = &.{};
    }
};

const ScoredNode = struct {
    node_index: usize,
    score: f32,
};

const EntryPoint = struct {
    node_index: usize,
    level: usize,
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
    entry: ?EntryPoint,
    prng: std.Random.DefaultPrng,
    point_norms: std.ArrayList(f32),
    visit_marks: std.ArrayList(u32),
    visit_epoch: u32,
    scratch_candidates: std.ArrayList(ScoredNode),
    scratch_results: std.ArrayList(ScoredNode),
    scratch_touched: std.ArrayList(usize),
    scratch_prune: std.ArrayList(ScoredNode),

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
            .entry = null,
            .prng = std.Random.DefaultPrng.init(config.seed),
            .point_norms = .empty,
            .visit_marks = .empty,
            .visit_epoch = 1,
            .scratch_candidates = .empty,
            .scratch_results = .empty,
            .scratch_touched = .empty,
            .scratch_prune = .empty,
        };
    }

    pub fn deinit(self: *HnswIndex) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.point_norms.deinit(self.allocator);
        self.visit_marks.deinit(self.allocator);
        self.scratch_candidates.deinit(self.allocator);
        self.scratch_results.deinit(self.allocator);
        self.scratch_touched.deinit(self.allocator);
        self.scratch_prune.deinit(self.allocator);
        self.entry = null;
    }

    pub fn build(self: *HnswIndex, points: []const Point) !void {
        self.clearGraph();
        try self.precomputePointNorms(points);
        try self.ensureVisitMarksLen(points.len);
        for (points, 0..) |point, point_index| {
            try self.insert(points, point_index, point.vector);
        }
    }

    pub fn insert(self: *HnswIndex, points: []const Point, point_index: usize, point_vector: []const f32) !void {
        try vector.ensureDimension(point_vector, self.dimension);
        if (self.visit_marks.items.len < self.nodes.items.len + 1) {
            try self.ensureVisitMarksLen(self.nodes.items.len + 1);
        }
        const query_norm = try vector.norm(point_vector);
        const level = self.randomLevel();
        const node_index = try self.addNode(point_index, level);

        if (self.entry == null) {
            self.entry = .{ .node_index = node_index, .level = level };
            return;
        }

        var current = self.entry.?.node_index;
        var layer: isize = @as(isize, @intCast(self.entry.?.level));
        while (layer > @as(isize, @intCast(level))) : (layer -= 1) {
            current = try self.greedySearchAtLayer(
                points,
                point_vector,
                query_norm,
                current,
                @as(usize, @intCast(layer)),
            );
        }

        const connect_max_layer = @min(self.entry.?.level, level);
        var l: isize = @as(isize, @intCast(connect_max_layer));
        while (l >= 0) : (l -= 1) {
            const layer_usize: usize = @intCast(l);
            const epoch = self.nextVisitEpoch();
            try self.searchLayerInPlace(
                points,
                point_vector,
                query_norm,
                current,
                self.config.ef_construction,
                layer_usize,
                epoch,
            );
            std.mem.sort(ScoredNode, self.scratch_results.items, {}, lessThanByScoreDesc);
            const neighbor_count = @min(self.config.m, self.scratch_results.items.len);
            self.scratch_touched.clearRetainingCapacity();
            for (self.scratch_results.items[0..neighbor_count]) |candidate| {
                try self.addUniqueNeighbor(node_index, layer_usize, candidate.node_index);
                try self.addUniqueNeighbor(candidate.node_index, layer_usize, node_index);
                try self.scratch_touched.append(self.allocator, candidate.node_index);
            }
            try self.pruneLayer(points, node_index, layer_usize);
            for (self.scratch_touched.items) |touched_node| {
                try self.pruneLayer(points, touched_node, layer_usize);
            }
            if (self.scratch_results.items.len > 0) {
                current = self.scratch_results.items[0].node_index;
            }
        }

        if (self.entry == null or level > self.entry.?.level) {
            self.entry = .{ .node_index = node_index, .level = level };
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
        const query_norm = try vector.norm(query);

        var current = self.entry.?.node_index;
        var layer: isize = @as(isize, @intCast(self.entry.?.level));
        while (layer > 0) : (layer -= 1) {
            current = try self.greedySearchAtLayer(points, query, query_norm, current, @as(usize, @intCast(layer)));
        }

        var mutable_self = @constCast(self);
        if (mutable_self.visit_marks.items.len < mutable_self.nodes.items.len) {
            try mutable_self.ensureVisitMarksLen(mutable_self.nodes.items.len);
        }
        const epoch = mutable_self.nextVisitEpoch();
        try mutable_self.searchLayerInPlace(points, query, query_norm, current, ef, 0, epoch);
        std.mem.sort(ScoredNode, mutable_self.scratch_results.items, {}, lessThanByScoreDesc);

        const result_count = @min(top_k, mutable_self.scratch_results.items.len);
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
            const point = points[self.nodes.items[mutable_self.scratch_results.items[idx].node_index].point_index];
            results[idx] = .{
                .id = try self.allocator.dupe(u8, point.id),
                .score = mutable_self.scratch_results.items[idx].score,
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
        self.point_norms.clearRetainingCapacity();
        self.visit_marks.clearRetainingCapacity();
        self.scratch_candidates.clearRetainingCapacity();
        self.scratch_results.clearRetainingCapacity();
        self.scratch_touched.clearRetainingCapacity();
        self.scratch_prune.clearRetainingCapacity();
        self.entry = null;
        self.prng = std.Random.DefaultPrng.init(self.config.seed);
        self.visit_epoch = 1;
    }

    fn precomputePointNorms(self: *HnswIndex, points: []const Point) !void {
        self.point_norms.clearRetainingCapacity();
        try self.point_norms.ensureTotalCapacity(self.allocator, points.len);
        for (points) |point| {
            const norm = try vector.norm(point.vector);
            if (norm == 0.0) return MnemeError.ZeroVector;
            try self.point_norms.append(self.allocator, norm);
        }
    }

    fn ensureVisitMarksLen(self: *HnswIndex, len: usize) !void {
        self.visit_marks.clearRetainingCapacity();
        try self.visit_marks.ensureTotalCapacity(self.allocator, len);
        if (len > 0) {
            try self.visit_marks.appendNTimes(self.allocator, 0, len);
        }
    }

    fn nextVisitEpoch(self: *HnswIndex) u32 {
        if (self.visit_epoch == std.math.maxInt(u32)) {
            @memset(self.visit_marks.items, 0);
            self.visit_epoch = 1;
            return self.visit_epoch;
        }
        self.visit_epoch += 1;
        return self.visit_epoch;
    }

    fn randomLevel(self: *HnswIndex) usize {
        var level: usize = 0;
        var rng = self.prng.random();
        // Keep level generation bounded and deterministic for Phase 3.
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
        query_norm: f32,
        start_node: usize,
        layer: usize,
    ) !usize {
        var current = start_node;
        var current_score = try self.similarity(points, current, query, query_norm);
        var improved = true;
        while (improved) {
            improved = false;
            for (self.nodes.items[current].neighbors_by_layer[layer].items) |neighbor| {
                const neighbor_score = try self.similarity(points, neighbor, query, query_norm);
                if (neighbor_score > current_score) {
                    current = neighbor;
                    current_score = neighbor_score;
                    improved = true;
                }
            }
        }
        return current;
    }

    fn searchLayerInPlace(
        self: *HnswIndex,
        points: []const Point,
        query: []const f32,
        query_norm: f32,
        entry_node: usize,
        ef: usize,
        layer: usize,
        epoch: u32,
    ) !void {
        self.scratch_candidates.clearRetainingCapacity();
        self.scratch_results.clearRetainingCapacity();

        const entry_score = try self.similarity(points, entry_node, query, query_norm);
        try self.scratch_candidates.append(self.allocator, .{ .node_index = entry_node, .score = entry_score });
        try self.scratch_results.append(self.allocator, .{ .node_index = entry_node, .score = entry_score });
        self.visit_marks.items[entry_node] = epoch;
        var worst_idx: usize = 0;
        var worst_score: f32 = entry_score;

        while (self.scratch_candidates.items.len > 0) {
            const best_idx = bestCandidateIndex(self.scratch_candidates.items);
            const candidate = self.scratch_candidates.swapRemove(best_idx);
            if (self.scratch_results.items.len >= ef and candidate.score < worst_score) break;

            for (self.nodes.items[candidate.node_index].neighbors_by_layer[layer].items) |neighbor| {
                if (self.visit_marks.items[neighbor] == epoch) continue;
                self.visit_marks.items[neighbor] = epoch;

                const score = try self.similarity(points, neighbor, query, query_norm);
                if (self.scratch_results.items.len < ef or score > worst_score) {
                    try self.scratch_candidates.append(self.allocator, .{ .node_index = neighbor, .score = score });
                    try self.scratch_results.append(self.allocator, .{ .node_index = neighbor, .score = score });
                    const appended_idx = self.scratch_results.items.len - 1;
                    if (score < worst_score) {
                        worst_idx = appended_idx;
                        worst_score = score;
                    }
                    if (self.scratch_results.items.len > ef) {
                        _ = self.scratch_results.swapRemove(worst_idx);
                        const worst = recomputeWorst(self.scratch_results.items);
                        worst_idx = worst.idx;
                        worst_score = worst.score;
                    }
                }
            }
        }
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
        const query_norm = if (self.nodes.items[node_index].point_index < self.point_norms.items.len)
            self.point_norms.items[self.nodes.items[node_index].point_index]
        else
            try vector.norm(query_vector);
        self.scratch_prune.clearRetainingCapacity();
        for (list.items) |neighbor| {
            const score = try self.similarity(points, neighbor, query_vector, query_norm);
            try self.scratch_prune.append(self.allocator, .{ .node_index = neighbor, .score = score });
        }
        std.mem.sort(ScoredNode, self.scratch_prune.items, {}, lessThanByScoreDesc);
        list.clearRetainingCapacity();
        const keep = @min(self.config.m, self.scratch_prune.items.len);
        for (self.scratch_prune.items[0..keep]) |item| {
            try list.append(self.allocator, item.node_index);
        }
    }

    fn similarity(
        self: *const HnswIndex,
        points: []const Point,
        node_index: usize,
        query: []const f32,
        query_norm: f32,
    ) !f32 {
        const point = points[self.nodes.items[node_index].point_index];
        return switch (self.metric) {
            .cosine => self.cosineSimilarityCached(
                self.nodes.items[node_index].point_index,
                point.vector,
                query,
                query_norm,
            ),
        };
    }

    fn cosineSimilarityCached(
        self: *const HnswIndex,
        point_index: usize,
        point_vector: []const f32,
        query: []const f32,
        query_norm: f32,
    ) !f32 {
        const dot_product = try vector.dot(point_vector, query);
        const norm_a = if (point_index < self.point_norms.items.len)
            self.point_norms.items[point_index]
        else
            try vector.norm(point_vector);
        const norm_b = query_norm;
        if (norm_a == 0.0 or norm_b == 0.0) return MnemeError.ZeroVector;
        return dot_product / (norm_a * norm_b);
    }

    pub fn stats(self: *const HnswIndex, allocator: std.mem.Allocator) !HnswStats {
        const max_level = if (self.entry) |entry| @as(isize, @intCast(entry.level)) else -1;
        const level_len: usize = if (max_level < 0) 0 else @as(usize, @intCast(max_level)) + 1;
        const level_counts = try allocator.alloc(usize, level_len);
        @memset(level_counts, 0);

        var total_degree_layer0: usize = 0;
        for (self.nodes.items) |node| {
            if (node.level < level_counts.len) level_counts[node.level] += 1;
            if (node.neighbors_by_layer.len > 0) total_degree_layer0 += node.neighbors_by_layer[0].items.len;
        }

        const avg_degree_layer0 = if (self.nodes.items.len == 0)
            0.0
        else
            @as(f64, @floatFromInt(total_degree_layer0)) / @as(f64, @floatFromInt(self.nodes.items.len));

        return .{
            .node_count = self.nodes.items.len,
            .max_level = max_level,
            .avg_degree_layer0 = avg_degree_layer0,
            .level_counts = level_counts,
            .allocator = allocator,
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

const WorstResult = struct {
    idx: usize,
    score: f32,
};

fn recomputeWorst(results: []const ScoredNode) WorstResult {
    const idx = worstResultIndex(results);
    return .{ .idx = idx, .score = results[idx].score };
}

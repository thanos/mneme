const std = @import("std");
const mneme = @import("mneme.zig");

pub const mneme_status_t = u32;
pub const MNEME_OK: mneme_status_t = 0;
pub const MNEME_ERROR_INVALID_ARGUMENT: mneme_status_t = 1;
pub const MNEME_ERROR_OUT_OF_MEMORY: mneme_status_t = 2;
pub const MNEME_ERROR_DIMENSION_MISMATCH: mneme_status_t = 3;
pub const MNEME_ERROR_IO: mneme_status_t = 4;
pub const MNEME_ERROR_INDEX_NOT_BUILT: mneme_status_t = 5;
pub const MNEME_ERROR_INDEX_STALE: mneme_status_t = 6;
pub const MNEME_ERROR_INTERNAL: mneme_status_t = 255;

pub const mneme_metric_t = u32;
pub const MNEME_METRIC_COSINE: mneme_metric_t = 1;
pub const MNEME_EF_SEARCH_DEFAULT: u32 = 0;

pub const mneme_hnsw_config_t = extern struct {
    m: u32,
    ef_construction: u32,
    ef_search: u32,
    seed: u64,
};

pub const mneme_collection_t = opaque {};
pub const mneme_results_t = opaque {};

const CCollection = struct {
    collection: mneme.Collection,
    mutex: SpinLock = .{},
};

const SpinLock = struct {
    state: std.atomic.Value(u8) = .init(0),

    fn lock(self: *SpinLock) void {
        var spins: u32 = 0;
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            spins += 1;
            if (spins < 64) {
                std.atomic.spinLoopHint();
            } else {
                std.Thread.yield() catch {};
            }
        }
    }

    fn unlock(self: *SpinLock) void {
        std.debug.assert(self.state.load(.monotonic) == 1);
        self.state.store(0, .release);
    }
};

const CResultItem = struct {
    id_z: [:0]u8,
    score: f32,
};

const CResults = struct {
    items: []CResultItem,
};

const abi_allocator = std.heap.page_allocator;
const ABI_VERSION: u32 = 1;

threadlocal var last_error_buf: [512:0]u8 = [_:0]u8{0} ** 512;

fn setLastError(msg: []const u8) void {
    const limit = last_error_buf.len - 1;
    const n = @min(msg.len, limit);
    @memcpy(last_error_buf[0..n], msg[0..n]);
    last_error_buf[n] = 0;
}

fn clearLastError() void {
    last_error_buf[0] = 0;
}

fn mapError(err: anyerror) mneme_status_t {
    setLastError(@errorName(err));
    return switch (err) {
        error.OutOfMemory => MNEME_ERROR_OUT_OF_MEMORY,
        mneme.MnemeError.InvalidDimension,
        mneme.MnemeError.EmptyVector,
        mneme.MnemeError.VectorLengthMismatch,
        => MNEME_ERROR_DIMENSION_MISMATCH,
        mneme.MnemeError.IndexNotBuilt => MNEME_ERROR_INDEX_NOT_BUILT,
        mneme.MnemeError.IndexStale => MNEME_ERROR_INDEX_STALE,
        mneme.MnemeError.DuplicateId,
        mneme.MnemeError.IdNotFound,
        mneme.MnemeError.InvalidIndexConfig,
        mneme.MnemeError.InvalidEfSearch,
        mneme.MnemeError.ZeroVector,
        => MNEME_ERROR_INVALID_ARGUMENT,
        mneme.MnemeError.InvalidMagic,
        mneme.MnemeError.UnsupportedVersion,
        mneme.MnemeError.TruncatedFile,
        mneme.MnemeError.CorruptRecord,
        mneme.MnemeError.InvalidMetric,
        error.FileNotFound,
        error.PathAlreadyExists,
        error.AccessDenied,
        error.NotDir,
        error.NameTooLong,
        error.NoSpaceLeft,
        error.InputOutput,
        => MNEME_ERROR_IO,
        else => MNEME_ERROR_INTERNAL,
    };
}

fn asCollection(handle: *mneme_collection_t) *CCollection {
    return @ptrCast(@alignCast(handle));
}

fn asResults(handle: *mneme_results_t) *CResults {
    return @ptrCast(@alignCast(handle));
}

fn asResultsConst(handle: *const mneme_results_t) *const CResults {
    return @ptrCast(@alignCast(handle));
}

fn floatSlice(ptr: ?[*]const f32, len: usize) ?[]const f32 {
    if (len == 0) return &.{};
    if (ptr == null) return null;
    return ptr.?[0..len];
}

fn metricFromC(metric: mneme_metric_t) ?mneme.Metric {
    if (metric == MNEME_METRIC_COSINE) return .cosine;
    return null;
}

fn convertAndTakeResults(
    collection: *mneme.Collection,
    raw_results: []mneme.SearchResult,
    out_results: *?*mneme_results_t,
) !void {
    defer collection.freeSearchResults(raw_results);

    const c_results = try abi_allocator.create(CResults);
    errdefer abi_allocator.destroy(c_results);

    c_results.items = try abi_allocator.alloc(CResultItem, raw_results.len);
    var initialized: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < initialized) : (i += 1) {
            abi_allocator.free(c_results.items[i].id_z);
        }
        abi_allocator.free(c_results.items);
    }

    for (raw_results, 0..) |result, idx| {
        c_results.items[idx] = .{
            .id_z = try abi_allocator.dupeSentinel(u8, result.id, 0),
            .score = result.score,
        };
        initialized += 1;
    }
    out_results.* = @ptrCast(c_results);
}

pub export fn mneme_abi_version() u32 {
    return ABI_VERSION;
}

pub export fn mneme_last_error() [*:0]const u8 {
    return &last_error_buf;
}

pub export fn mneme_collection_create(
    name: ?[*:0]const u8,
    dimension: u32,
    metric: mneme_metric_t,
    out_collection: ?*?*mneme_collection_t,
) mneme_status_t {
    if (out_collection == null or name == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    out_collection.?.* = null;
    const resolved_metric = metricFromC(metric) orelse {
        setLastError("InvalidMetric");
        return MNEME_ERROR_INVALID_ARGUMENT;
    };

    const dim: usize = dimension;
    var collection = mneme.Collection.init(abi_allocator, std.mem.span(name.?), dim, resolved_metric) catch |err| {
        return mapError(err);
    };
    errdefer collection.deinit();

    const handle = abi_allocator.create(CCollection) catch |err| return mapError(err);
    handle.* = .{ .collection = collection };
    out_collection.?.* = @ptrCast(handle);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_free(collection: ?*mneme_collection_t) void {
    if (collection == null) return;
    const inner = asCollection(collection.?);
    inner.collection.deinit();
    abi_allocator.destroy(inner);
}

pub export fn mneme_collection_insert(
    collection: ?*mneme_collection_t,
    id: ?[*:0]const u8,
    vector: ?[*]const f32,
    vector_len: u32,
    metadata: ?[*:0]const u8,
) mneme_status_t {
    if (collection == null or id == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    const vector_slice = floatSlice(vector, vector_len) orelse {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    };
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    const metadata_slice: ?[]const u8 = if (metadata) |m| std.mem.span(m) else null;
    coll_handle.collection.insert(std.mem.span(id.?), vector_slice, metadata_slice) catch |err| {
        return mapError(err);
    };
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_insert_batch(
    collection: ?*mneme_collection_t,
    ids: ?[*]const ?[*:0]const u8,
    vectors: ?[*]const f32,
    vector_len: u32,
    metadata: ?[*]const ?[*:0]const u8,
    count: u32,
    out_inserted: ?*u32,
) mneme_status_t {
    if (out_inserted) |ptr| ptr.* = 0;
    if (collection == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    if (count == 0) {
        clearLastError();
        return MNEME_OK;
    }
    if (ids == null or vectors == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }

    const dim: usize = @intCast(vector_len);
    const n: usize = @intCast(count);
    const total = std.math.mul(usize, n, dim) catch {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    };
    const ids_slice = ids.?[0..n];
    const vectors_slice = vectors.?[0..total];
    const metadata_slice: ?[]const ?[*:0]const u8 = if (metadata) |m| m[0..n] else null;
    var inserted: usize = 0;
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    var coll = &coll_handle.collection;
    while (inserted < n) : (inserted += 1) {
        const id_ptr = ids_slice[inserted] orelse {
            setLastError("InvalidArgument");
            return MNEME_ERROR_INVALID_ARGUMENT;
        };
        const start = inserted * dim;
        const vector = vectors_slice[start .. start + dim];
        const metadata_value: ?[]const u8 = if (metadata_slice) |m| blk: {
            if (m[inserted]) |v| break :blk std.mem.span(v);
            break :blk null;
        } else null;
        coll.insert(std.mem.span(id_ptr), vector, metadata_value) catch |err| {
            if (out_inserted) |ptr| ptr.* = @intCast(inserted);
            return mapError(err);
        };
    }
    if (out_inserted) |ptr| ptr.* = @intCast(inserted);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_delete(
    collection: ?*mneme_collection_t,
    id: ?[*:0]const u8,
) mneme_status_t {
    if (collection == null or id == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    coll_handle.collection.delete(std.mem.span(id.?)) catch |err| {
        return mapError(err);
    };
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_delete_batch(
    collection: ?*mneme_collection_t,
    ids: ?[*]const ?[*:0]const u8,
    count: u32,
    out_deleted: ?*u32,
) mneme_status_t {
    if (out_deleted) |ptr| ptr.* = 0;
    if (collection == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    if (count == 0) {
        clearLastError();
        return MNEME_OK;
    }
    if (ids == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    const n: usize = @intCast(count);
    const ids_slice = ids.?[0..n];
    var deleted: usize = 0;
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    var coll = &coll_handle.collection;
    while (deleted < n) : (deleted += 1) {
        const id_ptr = ids_slice[deleted] orelse {
            setLastError("InvalidArgument");
            return MNEME_ERROR_INVALID_ARGUMENT;
        };
        coll.delete(std.mem.span(id_ptr)) catch |err| {
            if (out_deleted) |ptr| ptr.* = @intCast(deleted);
            return mapError(err);
        };
    }
    if (out_deleted) |ptr| ptr.* = @intCast(deleted);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_count(collection: ?*mneme_collection_t) u64 {
    if (collection == null) {
        setLastError("InvalidArgument");
        return 0;
    }
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    clearLastError();
    return @intCast(coll_handle.collection.count());
}

pub export fn mneme_collection_search_flat(
    collection: ?*mneme_collection_t,
    query: ?[*]const f32,
    query_len: u32,
    top_k: u32,
    out_results: ?*?*mneme_results_t,
) mneme_status_t {
    if (collection == null or out_results == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    out_results.?.* = null;
    const query_slice = floatSlice(query, query_len) orelse {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    };
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    var coll = &coll_handle.collection;
    const raw = coll.search(query_slice, @intCast(top_k)) catch |err| return mapError(err);
    convertAndTakeResults(coll, raw, out_results.?) catch |err| return mapError(err);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_build_hnsw(
    collection: ?*mneme_collection_t,
    config: ?*const mneme_hnsw_config_t,
) mneme_status_t {
    if (collection == null or config == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    const cfg = config.?.*;
    coll_handle.collection.buildHnsw(.{
        .m = cfg.m,
        .ef_construction = cfg.ef_construction,
        .ef_search = cfg.ef_search,
        .seed = cfg.seed,
    }) catch |err| return mapError(err);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_search_hnsw(
    collection: ?*mneme_collection_t,
    query: ?[*]const f32,
    query_len: u32,
    top_k: u32,
    ef_search: u32,
    out_results: ?*?*mneme_results_t,
) mneme_status_t {
    if (collection == null or out_results == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    out_results.?.* = null;
    const query_slice = floatSlice(query, query_len) orelse {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    };
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    var coll = &coll_handle.collection;
    const search_options = mneme.SearchOptions{
        .index = .hnsw,
        .ef_search = if (ef_search == MNEME_EF_SEARCH_DEFAULT) null else @as(usize, ef_search),
    };
    const raw = coll.searchWithOptions(query_slice, @intCast(top_k), search_options) catch |err| return mapError(err);
    convertAndTakeResults(coll, raw, out_results.?) catch |err| return mapError(err);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_save(
    collection: ?*mneme_collection_t,
    path: ?[*:0]const u8,
) mneme_status_t {
    if (collection == null or path == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    const coll_handle = asCollection(collection.?);
    coll_handle.mutex.lock();
    defer coll_handle.mutex.unlock();
    coll_handle.collection.saveToFile(std.mem.span(path.?)) catch |err| return mapError(err);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_collection_load(
    path: ?[*:0]const u8,
    out_collection: ?*?*mneme_collection_t,
) mneme_status_t {
    if (path == null or out_collection == null) {
        setLastError("InvalidArgument");
        return MNEME_ERROR_INVALID_ARGUMENT;
    }
    out_collection.?.* = null;
    var collection = mneme.Collection.loadFromFile(abi_allocator, std.mem.span(path.?)) catch |err| {
        return mapError(err);
    };
    errdefer collection.deinit();

    const handle = abi_allocator.create(CCollection) catch |err| return mapError(err);
    handle.* = .{ .collection = collection };
    out_collection.?.* = @ptrCast(handle);
    clearLastError();
    return MNEME_OK;
}

pub export fn mneme_results_len(results: ?*const mneme_results_t) u32 {
    if (results == null) {
        setLastError("InvalidArgument");
        return 0;
    }
    return @intCast(asResultsConst(results.?).items.len);
}

pub export fn mneme_results_id(results: ?*const mneme_results_t, index: u32) ?[*:0]const u8 {
    if (results == null) {
        setLastError("InvalidArgument");
        return null;
    }
    const resolved = asResultsConst(results.?);
    const idx: usize = @intCast(index);
    if (idx >= resolved.items.len) {
        setLastError("InvalidArgument");
        return null;
    }
    return resolved.items[idx].id_z.ptr;
}

pub export fn mneme_results_score(results: ?*const mneme_results_t, index: u32) f32 {
    if (results == null) {
        setLastError("InvalidArgument");
        return 0.0;
    }
    const resolved = asResultsConst(results.?);
    const idx: usize = @intCast(index);
    if (idx >= resolved.items.len) {
        setLastError("InvalidArgument");
        return 0.0;
    }
    return resolved.items[idx].score;
}

pub export fn mneme_results_free(results: ?*mneme_results_t) void {
    if (results == null) return;
    const resolved = asResults(results.?);
    for (resolved.items) |item| {
        abi_allocator.free(item.id_z);
    }
    abi_allocator.free(resolved.items);
    abi_allocator.destroy(resolved);
}

const std = @import("std");

pub const Point = struct {
    id: []u8,
    vector: []f32,
    metadata: ?[]u8,

    pub fn init(
        allocator: std.mem.Allocator,
        id: []const u8,
        input_vector: []const f32,
        metadata: ?[]const u8,
    ) !Point {
        const owned_id = try allocator.dupe(u8, id);
        errdefer allocator.free(owned_id);

        const owned_vector = try allocator.dupe(f32, input_vector);
        errdefer allocator.free(owned_vector);

        var owned_metadata: ?[]u8 = null;
        if (metadata) |value| {
            owned_metadata = try allocator.dupe(u8, value);
        }
        errdefer if (owned_metadata) |value| allocator.free(value);

        return Point{
            .id = owned_id,
            .vector = owned_vector,
            .metadata = owned_metadata,
        };
    }

    pub fn deinit(self: *Point, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.vector);
        if (self.metadata) |value| allocator.free(value);
    }
};

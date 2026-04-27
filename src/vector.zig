const std = @import("std");
const MnemeError = @import("errors.zig").MnemeError;

pub fn ensureDimension(vector: []const f32, expected: usize) !void {
    if (expected == 0) return MnemeError.InvalidDimension;
    if (vector.len == 0) return MnemeError.EmptyVector;
    if (vector.len != expected) return MnemeError.InvalidDimension;
}

pub fn dot(a: []const f32, b: []const f32) !f32 {
    if (a.len == 0 or b.len == 0) return MnemeError.EmptyVector;
    if (a.len != b.len) return MnemeError.InvalidDimension;

    var acc: f32 = 0.0;
    for (a, b) |left, right| {
        acc += left * right;
    }
    return acc;
}

pub fn norm(vector: []const f32) !f32 {
    if (vector.len == 0) return MnemeError.EmptyVector;

    var sum_sq: f32 = 0.0;
    for (vector) |value| {
        sum_sq += value * value;
    }
    return std.math.sqrt(sum_sq);
}

pub fn isZeroVector(vector: []const f32) bool {
    for (vector) |value| {
        if (value != 0.0) return false;
    }
    return true;
}

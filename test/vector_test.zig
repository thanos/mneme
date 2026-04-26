const std = @import("std");
const mneme = @import("mneme");

test "valid dimension passes" {
    const vec = [_]f32{ 1.0, 2.0, 3.0 };
    try mneme.vector.ensureDimension(&vec, 3);
}

test "dimension mismatch fails" {
    const vec = [_]f32{ 1.0, 2.0, 3.0 };
    try std.testing.expectError(mneme.MnemeError.InvalidDimension, mneme.vector.ensureDimension(&vec, 2));
}

test "zero vector detection works" {
    const zero = [_]f32{ 0.0, 0.0, 0.0 };
    const non_zero = [_]f32{ 0.0, 1.0, 0.0 };
    try std.testing.expect(mneme.vector.isZeroVector(&zero));
    try std.testing.expect(!mneme.vector.isZeroVector(&non_zero));
}

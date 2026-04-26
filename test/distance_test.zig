const std = @import("std");
const mneme = @import("mneme");

test "identical vectors return high similarity" {
    const a = [_]f32{ 1.0, 2.0, 3.0 };
    const sim = try mneme.distance.cosineSimilarity(&a, &a);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), sim, 0.0001);
}

test "orthogonal vectors return near zero similarity" {
    const a = [_]f32{ 1.0, 0.0, 0.0 };
    const b = [_]f32{ 0.0, 1.0, 0.0 };
    const sim = try mneme.distance.cosineSimilarity(&a, &b);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), sim, 0.0001);
}

test "zero vectors are handled safely" {
    const a = [_]f32{ 0.0, 0.0, 0.0 };
    const b = [_]f32{ 1.0, 2.0, 3.0 };
    try std.testing.expectError(mneme.MnemeError.ZeroVector, mneme.distance.cosineSimilarity(&a, &b));
}

test "mismatched dimensions return error" {
    const a = [_]f32{ 1.0, 2.0, 3.0 };
    const b = [_]f32{ 1.0, 2.0 };
    try std.testing.expectError(mneme.MnemeError.InvalidDimension, mneme.distance.cosineSimilarity(&a, &b));
}

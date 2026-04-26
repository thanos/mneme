const MnemeError = @import("errors.zig").MnemeError;
const vector = @import("vector.zig");

pub fn cosineSimilarity(a: []const f32, b: []const f32) !f32 {
    const dot_product = try vector.dot(a, b);
    const norm_a = try vector.norm(a);
    const norm_b = try vector.norm(b);

    if (norm_a == 0.0 or norm_b == 0.0) return MnemeError.ZeroVector;

    return dot_product / (norm_a * norm_b);
}

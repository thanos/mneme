const std = @import("std");
const zlinter = @import("zlinter");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mneme_module = b.createModule(.{
        .root_source_file = b.path("src/mneme.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "mneme",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addImport("mneme", mneme_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run benchmark executable");
    run_step.dependOn(&run_cmd.step);

    const lint_step = b.step("lint", "Lint Zig source with zlinter");
    lint_step.dependOn(step: {
        var builder = zlinter.builder(b, .{ .optimize = .ReleaseFast });
        builder.addPaths(.{
            .include = &.{ b.path("src"), b.path("test"), b.path("build.zig") },
            .exclude = &.{},
        });
        builder.addRule(.{ .builtin = .no_unused }, .{});
        builder.addRule(.{ .builtin = .no_deprecated }, .{});
        builder.addRule(.{ .builtin = .no_orelse_unreachable }, .{});
        break :step builder.build();
    });

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mneme.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_root_tests = b.addRunArtifact(root_tests);

    const vector_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/vector_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vector_tests.root_module.addImport("mneme", mneme_module);
    const run_vector_tests = b.addRunArtifact(vector_tests);

    const distance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/distance_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    distance_tests.root_module.addImport("mneme", mneme_module);
    const run_distance_tests = b.addRunArtifact(distance_tests);

    const collection_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/collection_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    collection_tests.root_module.addImport("mneme", mneme_module);
    const run_collection_tests = b.addRunArtifact(collection_tests);

    const index_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/index_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    index_tests.root_module.addImport("mneme", mneme_module);
    const run_index_tests = b.addRunArtifact(index_tests);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_vector_tests.step);
    test_step.dependOn(&run_distance_tests.step);
    test_step.dependOn(&run_collection_tests.step);
    test_step.dependOn(&run_index_tests.step);
}

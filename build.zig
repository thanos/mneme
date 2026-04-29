const std = @import("std");
const zlinter = @import("zlinter");

fn addMnemeTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mneme_module: *std.Build.Module,
    test_path: []const u8,
) *std.Build.Step.Run {
    const test_artifact = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(test_path),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_artifact.root_module.addImport("mneme", mneme_module);
    return b.addRunArtifact(test_artifact);
}

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

    const shared_lib = b.addLibrary(.{
        .name = "mneme",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/c_api.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(shared_lib);
    shared_lib.installHeader(b.path("include/mneme.h"), "mneme.h");

    const lib_step = b.step("lib", "Build shared C ABI library");
    lib_step.dependOn(b.getInstallStep());

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

    const run_vector_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/vector_test.zig",
    );
    const run_distance_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/distance_test.zig",
    );
    const run_collection_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/collection_test.zig",
    );
    const run_index_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/index_test.zig",
    );
    const run_codec_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/codec_test.zig",
    );
    const run_storage_roundtrip_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/storage_roundtrip_test.zig",
    );
    const run_storage_failure_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/storage_failure_test.zig",
    );
    const run_hnsw_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_test.zig",
    );
    const run_hnsw_recall_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_recall_test.zig",
    );
    const run_hnsw_collection_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_collection_test.zig",
    );
    const run_c_api_tests = addMnemeTest(
        b,
        target,
        optimize,
        mneme_module,
        "test/c_api_test.zig",
    );

    const install_lib_dir = b.getInstallPath(.lib, "");
    const install_header_dir = b.getInstallPath(.header, "");
    const smoke_bin_path = b.getInstallPath(.bin, "mneme_c_smoke");
    const compile_c_example = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    compile_c_example.addArg("examples/c/basic.c");
    compile_c_example.addArg(b.fmt("-I{s}", .{install_header_dir}));
    compile_c_example.addArg(b.fmt("-L{s}", .{install_lib_dir}));
    compile_c_example.addArg("-lmneme");
    compile_c_example.addArg(b.fmt("-Wl,-rpath,{s}", .{install_lib_dir}));
    compile_c_example.addArg("-o");
    compile_c_example.addArg(smoke_bin_path);
    compile_c_example.step.dependOn(b.getInstallStep());

    const run_c_example = b.addSystemCommand(&.{smoke_bin_path});
    run_c_example.step.dependOn(&compile_c_example.step);

    const c_integration_step = b.step("c-integration", "Compile and run C ABI smoke example");
    c_integration_step.dependOn(&run_c_example.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_vector_tests.step);
    test_step.dependOn(&run_distance_tests.step);
    test_step.dependOn(&run_collection_tests.step);
    test_step.dependOn(&run_index_tests.step);
    test_step.dependOn(&run_codec_tests.step);
    test_step.dependOn(&run_storage_roundtrip_tests.step);
    test_step.dependOn(&run_storage_failure_tests.step);
    test_step.dependOn(&run_hnsw_tests.step);
    test_step.dependOn(&run_hnsw_recall_tests.step);
    test_step.dependOn(&run_hnsw_collection_tests.step);
    test_step.dependOn(&run_c_api_tests.step);
}

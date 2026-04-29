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

fn addMnemeCoverageRun(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mneme_module: *std.Build.Module,
    test_path: []const u8,
    coverage_out_dir: []const u8,
) *std.Build.Step.Run {
    const test_artifact = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(test_path),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_artifact.root_module.addImport("mneme", mneme_module);

    const ensure_out_dir = b.addSystemCommand(&.{ "mkdir", "-p", coverage_out_dir });

    const kcov_run = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-path=src",
        coverage_out_dir,
    });
    kcov_run.step.dependOn(&ensure_out_dir.step);
    kcov_run.addFileArg(test_artifact.getEmittedBin());
    return kcov_run;
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
    const install_shared_lib = b.addInstallArtifact(shared_lib, .{});
    const install_shared_header = b.addInstallHeaderFile(b.path("include/mneme.h"), "mneme.h");

    const lib_step = b.step("lib", "Build shared C ABI library");
    lib_step.dependOn(&install_shared_lib.step);
    lib_step.dependOn(&install_shared_header.step);

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
    const ensure_smoke_bin_dir = b.addSystemCommand(&.{ "mkdir", "-p", b.getInstallPath(.bin, "") });
    const compile_c_example = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    compile_c_example.addArg("examples/c/basic.c");
    compile_c_example.addArg(b.fmt("-I{s}", .{install_header_dir}));
    compile_c_example.addArg(b.fmt("-L{s}", .{install_lib_dir}));
    compile_c_example.addArg("-lmneme");
    compile_c_example.addArg(b.fmt("-Wl,-rpath,{s}", .{install_lib_dir}));
    compile_c_example.addArg("-o");
    compile_c_example.addArg(smoke_bin_path);
    compile_c_example.step.dependOn(&ensure_smoke_bin_dir.step);
    compile_c_example.step.dependOn(&install_shared_lib.step);
    compile_c_example.step.dependOn(&install_shared_header.step);

    const run_c_example = b.addSystemCommand(&.{smoke_bin_path});
    run_c_example.step.dependOn(&compile_c_example.step);

    const c_integration_step = b.step("c-integration", "Compile and run C ABI smoke example");
    c_integration_step.dependOn(&run_c_example.step);

    const coverage_step = b.step("coverage", "Run test coverage with kcov");
    const coverage_c_integration_step = b.step(
        "coverage-c-integration",
        "Run kcov for C ABI smoke integration binary",
    );

    const coverage_vector_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/vector_test.zig",
        b.getInstallPath(.prefix, "kcov/vector"),
    );
    coverage_step.dependOn(&coverage_vector_tests.step);
    const coverage_distance_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/distance_test.zig",
        b.getInstallPath(.prefix, "kcov/distance"),
    );
    coverage_step.dependOn(&coverage_distance_tests.step);
    const coverage_collection_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/collection_test.zig",
        b.getInstallPath(.prefix, "kcov/collection"),
    );
    coverage_step.dependOn(&coverage_collection_tests.step);
    const coverage_index_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/index_test.zig",
        b.getInstallPath(.prefix, "kcov/index"),
    );
    coverage_step.dependOn(&coverage_index_tests.step);
    const coverage_codec_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/codec_test.zig",
        b.getInstallPath(.prefix, "kcov/codec"),
    );
    coverage_step.dependOn(&coverage_codec_tests.step);
    const coverage_storage_roundtrip_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/storage_roundtrip_test.zig",
        b.getInstallPath(.prefix, "kcov/storage_roundtrip"),
    );
    coverage_step.dependOn(&coverage_storage_roundtrip_tests.step);
    const coverage_storage_failure_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/storage_failure_test.zig",
        b.getInstallPath(.prefix, "kcov/storage_failure"),
    );
    coverage_step.dependOn(&coverage_storage_failure_tests.step);
    const coverage_hnsw_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_test.zig",
        b.getInstallPath(.prefix, "kcov/hnsw"),
    );
    coverage_step.dependOn(&coverage_hnsw_tests.step);
    const coverage_hnsw_recall_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_recall_test.zig",
        b.getInstallPath(.prefix, "kcov/hnsw_recall"),
    );
    coverage_step.dependOn(&coverage_hnsw_recall_tests.step);
    const coverage_hnsw_collection_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/hnsw_collection_test.zig",
        b.getInstallPath(.prefix, "kcov/hnsw_collection"),
    );
    coverage_step.dependOn(&coverage_hnsw_collection_tests.step);
    const coverage_c_api_tests = addMnemeCoverageRun(
        b,
        target,
        optimize,
        mneme_module,
        "test/c_api_test.zig",
        b.getInstallPath(.prefix, "kcov/c_api"),
    );
    coverage_step.dependOn(&coverage_c_api_tests.step);

    const c_smoke_coverage_out_dir = b.getInstallPath(.prefix, "kcov/c_integration");
    const ensure_c_smoke_coverage_out_dir = b.addSystemCommand(&.{ "mkdir", "-p", c_smoke_coverage_out_dir });
    const coverage_c_smoke = b.addSystemCommand(&.{
        "kcov",
        "--clean",
        "--include-path=src",
        c_smoke_coverage_out_dir,
        smoke_bin_path,
    });
    coverage_c_smoke.step.dependOn(&ensure_c_smoke_coverage_out_dir.step);
    coverage_c_smoke.step.dependOn(&compile_c_example.step);
    coverage_c_integration_step.dependOn(&coverage_c_smoke.step);

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

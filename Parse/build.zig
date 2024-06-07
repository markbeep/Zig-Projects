const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Parse",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const treesitter = b.dependency("tree-sitter", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(treesitter.artifact("tree-sitter"));

    const tsx = b.dependency("tree-sitter-typescript", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addCSourceFiles(.{ .files = &[_][]const u8{ "parser.c", "scanner.c" }, .root = tsx.path("tsx/src") });
    exe.addIncludePath(tsx.path("tsx/src"));
    exe.addIncludePath(tsx.path("bindings/c"));
    exe.installHeadersDirectory(tsx.path("bindings/c"), ".", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

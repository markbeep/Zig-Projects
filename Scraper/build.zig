const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "Scraper",
        .root_source_file = b.path("src/scraper.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "Scraper",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const libtidy = b.dependency("libtidy", .{
        .target = target,
        .optimize = optimize,
    });
    exe.installHeadersDirectory(libtidy.path("include"), ".", .{});
    exe.addIncludePath(libtidy.path("include"));
    exe.addCSourceFiles(.{
        .files = &[_][]const u8{ "access.c", "alloc.c", "attrdict.c", "attrs.c", "buffio.c", "charsets.c", "clean.c", "config.c", "entities.c", "fileio.c", "gdoc.c", "istack.c", "language.c", "lexer.c", "mappedio.c", "message.c", "messageobj.c", "parser.c", "pprint.c", "sprtf.c", "streamio.c", "tagask.c", "tags.c", "tidylib.c", "tmbstr.c", "utf8.c" },
        .root = libtidy.path("src"),
    });
    exe.linkLibC();

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/scraper.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

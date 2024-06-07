const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "backend",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("httpz", httpz.module("httpz"));

    const zul = b.dependency("zul", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zul", zul.module("zul"));

    const logz = b.dependency("logz", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("logz", logz.module("logz"));

    // hiredis c lib
    const hiredis = b.dependency("hiredis", .{
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addCSourceFiles(.{
        .root = hiredis.path(""),
        .files = &[_][]const u8{
            "alloc.c",
            "async.c",
            "dict.c",
            "hiredis.c",
            "net.c",
            "read.c",
            "sds.c",
            "sockcompat.c",
        },
        .flags = &[_][]const u8{
            "-Wall",
            "-W",
            "-Wstrict-prototypes",
            "-Wwrite-strings",
            "-Wno-missing-field-initializers",
        },
    });
    exe.installHeadersDirectory(hiredis.path(""), "", .{
        .include_extensions = &.{"hiredis.h"},
    });
    exe.addIncludePath(hiredis.path(""));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

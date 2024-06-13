const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    const lib = b.addExecutable(.{
        .name = "Wasm",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.entry = .disabled;
    lib.rdynamic = true;

    const install = b.addInstallArtifact(lib, .{});

    const ensure_dir = b.addSystemCommand(&[_][]const u8{
        "mkdir",
        "-p",
        "public",
    });
    ensure_dir.step.dependOn(&install.step);
    const move_wasm = b.addSystemCommand(&[_][]const u8{
        "cp",
        "zig-out/bin/Wasm.wasm",
        "public/add.wasm",
    });
    move_wasm.step.dependOn(&ensure_dir.step);

    b.getInstallStep().dependOn(&move_wasm.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

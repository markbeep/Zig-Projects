const std = @import("std");
const os = std.os;
const ui = @import("ui.zig");
const print = std.debug.print;

var term: ?ui.Terminal = null;

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.?.handleTerminalResize();
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    term = ui.Terminal.init(gpa.allocator(), null) catch return print("failed to initialize terminal", .{});
    defer term.?.deinit();

    os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null) catch return print("failed to change signal action for WINCH", .{});

    const tty = std.fs.cwd().openFile(
        "/dev/tty",
        .{ .mode = std.fs.File.OpenMode.read_write },
    ) catch return print("failed to open tty", .{});

    while (term.?.open) {
        var buf: [8]u8 = undefined;
        const size = tty.read(&buf) catch return print("failed to read tty", .{});
        if (size == 0) return;
        term.?.handleInput(buf) catch return print("failed to handle input", .{});
        term.?.render();
    }
}

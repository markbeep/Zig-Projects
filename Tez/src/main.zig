const std = @import("std");
const os = std.os;
const ui = @import("ui.zig");
const print = std.debug.print;
const testing = std.testing;

var term: ?ui.Terminal = null;

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.?.handleTerminalResize();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    term = try ui.Terminal.init(
        gpa.allocator(),
        .{ .setup_terminal = true },
    );
    defer term.?.deinit();

    try os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    const tty = std.fs.cwd().openFile(
        "/dev/tty",
        .{ .mode = std.fs.File.OpenMode.read_write },
    ) catch return print("failed to open tty", .{});

    while (term.?.open) {
        var buf: [8]u8 = undefined;
        const size = try tty.read(&buf);
        try term.?.handleInput(buf, size);
        term.?.render();
    }
}

test "main" {
    const terminal = try ui.Terminal.init(testing.allocator, .{ .setup_terminal = false });
    defer terminal.deinit();
}

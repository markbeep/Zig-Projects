const std = @import("std");
const os = std.os;
const t = @import("terminal.zig");

var term: ?t.Terminal = null;

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.?.checkTerminalSize() catch {};
    term.?.render() catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    term = try t.Terminal.init(gpa.allocator());
    defer term.?.deinit();
    try term.?.setupTerminal();
    defer term.?.restoreTerminal();

    try os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    try term.?.render();

    try term.?.listenForInput();
}

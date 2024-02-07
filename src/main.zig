const std = @import("std");
const os = std.os;
const ui = @import("ui.zig");

var term: ?ui.Terminal = null;

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.?.checkTerminalSize();
    term.?.render();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    term = try ui.Terminal.init(gpa.allocator());
    defer term.?.deinit();

    try os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);
}

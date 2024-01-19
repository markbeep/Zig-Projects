const std = @import("std");
const os = std.os;
const t = @import("terminal.zig");

var term = t.Terminal{};

fn handleSigInt(_: c_int) callconv(.C) void {
    term.open = false;
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.checkTerminalSize() catch unreachable;
    term.render() catch unreachable;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    try term.init(gpa.allocator());
    defer term.deinit();

    try std.os.sigaction(os.SIG.INT, &os.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    try std.os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    try term.render();

    const stdin = std.io.getStdIn().reader();
    while (term.open) {
        var buf: [3]u8 = undefined;
        const size = try stdin.read(&buf);
        if (size == 0) continue;
        try term.handleInput(buf);
        try term.render();
    }
}

test "terminal" {
    try term.init(std.testing.allocator);
    defer term.deinit();
}

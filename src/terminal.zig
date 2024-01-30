const std = @import("std");
const testing = std.testing;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const Allocator = std.mem.Allocator;

/// Type of cursor to use.
///
/// More information: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Functions-using-CSI-_-ordered-by-the-final-character-lparen-s-rparen:CSI-Ps-SP-q.1D81
const CursorMode = enum(u4) {
    blinkingBlock = 1,
    steadyBlock = 2,
    blinkingUnderline = 3,
    steadyUnderline = 4,
    blinkingBar = 5,
    steadyBar = 6,
};

const Mode = enum(u2) {
    normal,
    insert,
    visual,
};

const TerminalOptions = struct {
    filepath: []const u8,
};

pub const Terminal = struct {
    const Self = @This();

    x: usize = 0,
    y: usize = 0,
    content: GapBuffer(GapBuffer(u8)),
    allocator: Allocator,
    options: ?TerminalOptions,

    pub fn init(allocator: std.mem.Allocator, options: ?TerminalOptions) Allocator.Error!Self {
        var buffer = try GapBuffer(GapBuffer(u8)).initCapacity(allocator, 1000);
        const line = try GapBuffer(u8).initCapacity(allocator, 10);
        try buffer.insert(line);
        return Self{
            .content = buffer,
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: Self) void {
        var iterator = self.content.iterator();
        while (iterator.next()) |line| {
            line.deinit();
        }
        self.content.deinit();
    }
};

test "init" {
    var term = try Terminal.init(testing.allocator, null);
    defer term.deinit();
    try testing.expectEqual(@as(usize, 0), term.x);
    try testing.expectEqual(@as(usize, 0), term.y);
    try testing.expectEqual(@as(usize, 1), term.content.len);
    try testing.expectEqual(@as(usize, 0), term.content.buffer.items[0].len);
}

test "init with failing allocator" {
    const terminal = Terminal.init(testing.failing_allocator, null);
    try testing.expectError(std.mem.Allocator.Error.OutOfMemory, terminal);
}

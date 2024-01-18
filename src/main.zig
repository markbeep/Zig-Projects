const std = @import("std");
const os = std.os;

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("ctype.h");
    @cInclude("sys/ioctl.h");
});

const terminalErr = error{ GETADDR, SETADDR, IOCTL };

fn printabaleStrLen(str: *[]const u8) usize {
    var s = 0;
    for (str) |char| {
        if (c.isprint(char) != 0) s += 1;
    }
    return s;
}

const Terminal = struct {
    /// If the window should be open right now. Setting this to false will close the terminal.
    open: bool = false,
    orig_termios: c.termios = undefined,
    width: i32 = undefined,
    height: i32 = undefined,
    /// left is 0
    /// top is 0
    y: i32 = 0,
    x: i32 = 0,
    content: std.ArrayList(std.ArrayList(u8)) = undefined,
    allocator: std.mem.Allocator = undefined,

    const lineNumberPadding = 4;
    const xOffset = lineNumberPadding + 3;
    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;

        // save screen and clear it
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[?47h\x1b[2J", .{}); // save and clear screen

        // enters terminal raw mode
        // source: https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
        if (c.tcgetattr(c.STDIN_FILENO, &self.orig_termios) != 0)
            return terminalErr.GETADDR;
        var raw = self.orig_termios;
        raw.c_iflag &= ~(@as(u32, c.IXON | c.ICRNL | c.ISTRIP));
        raw.c_oflag &= ~(@as(u32, c.OPOST));
        raw.c_lflag &= ~(@as(u32, c.ECHO | c.ICANON | c.ISIG | c.IEXTEN));
        raw.c_cflag |= @as(u32, c.CS8);
        raw.c_cc[c.VMIN] = 0;
        raw.c_cc[c.VTIME] = 1; // 1=100ms
        if (c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw) != 0)
            return terminalErr.SETADDR;

        try self.checkTerminalSize();

        // initialize first line
        self.content = std.ArrayList(std.ArrayList(u8)).init(allocator);
        try self.content.append(std.ArrayList(u8).init(allocator));

        self.open = true;
    }

    pub fn deinit(self: *Self) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("\x1b[?47l", .{}) catch unreachable; // restore saved screen

        // restore terminal mode from before
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.orig_termios);

        for (self.content.items) |item| {
            item.deinit();
        }
        self.content.deinit();

        self.open = false;
    }

    /// Checks the current width and height of the terminal to adjust accordingly
    fn checkTerminalSize(self: *Self) !void {
        var w: c.winsize = undefined;
        if (c.ioctl(0, c.TIOCGWINSZ, &w) != 0)
            return terminalErr.IOCTL;
        self.width = w.ws_col;
        self.height = w.ws_row;
        if (self.width < self.x) self.x = self.width;
        if (self.height < self.y) self.y = self.height;
    }

    fn moveCursor(x: i32, y: i32) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[{d};{d}H", .{ y, x });
    }

    fn moveCursorBuffered(bw: anytype, x: i32, y: i32) !void {
        try bw.print("\x1b[{d};{d}H", .{ y, x });
    }

    fn render(self: *Self) !void {
        const stdout = std.io.getStdOut().writer();
        var buf = std.io.bufferedWriter(stdout);
        var bw = buf.writer();

        try bw.print("\x1b[2J", .{}); // erase screen

        for (self.content.items, 1..) |line, y| {
            try moveCursorBuffered(bw, 0, @intCast(y));
            try bw.print("\x1b[38;5;240m{d: >4} | \x1b[0m", .{y}); // grey line number
            for (line.items) |char| {
                try bw.print("{u}", .{char});
            }
        }

        // Draw name at bottom of editor
        try moveCursorBuffered(bw, 0, self.height);
        try bw.print("\x1b[1;43m    Tez  |  'q' to quit", .{});

        // fill bottom line
        for (23..@intCast(self.width)) |_| {
            try bw.print(" ", .{});
        }
        try bw.print("\x1b[0m", .{});

        // move cursor to where cursor should be
        try moveCursorBuffered(bw, self.x + 1 + xOffset, self.y + 1);

        try buf.flush();
    }

    fn setChar(self: *Self, char: u8) !void {
        switch (char) {
            '\n' => {
                // at the end of the line

                self.y += 1;
                self.x = 0;
                if (self.content.items.len <= self.y) {
                    try self.content.append(std.ArrayList(u8).init(self.allocator));
                } else {
                    try self.content.insert(@intCast(self.y), std.ArrayList(u8).init(self.allocator));
                }
            },
            else => {
                var line = &self.content.items[@intCast(self.y)];
                if (line.items.len <= self.x) {
                    try line.append(char);
                } else {
                    try line.insert(@intCast(self.x), char);
                }
                self.x += 1;
            },
        }
    }

    fn handleInput(self: *Self, buf: [3]u8) !void {
        const char = buf[0];
        if (char == 'q') {
            self.open = false;
            return;
        }
        if (char == 27) {
            const maxY: i32 = @intCast(self.content.items.len - 1);
            switch (buf[2]) {
                'A' => {
                    self.y = @max(0, self.y - 1);
                    const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                    self.x = @min(self.x, maxX);
                },
                'B' => {
                    self.y = @min(self.y + 1, maxY);
                    const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                    self.x = @min(self.x, maxX);
                },
                'C' => {
                    const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                    self.x = @min(self.x + 1, maxX);
                },
                'D' => {
                    self.x = @max(0, self.x - 1);
                },
                else => std.debug.print("UNKNWN = {u}\n\r", .{buf[2]}),
            }
        } else if (c.iscntrl(char) != 0) {
            switch (char) {
                13 => try self.setChar('\n'),
                127 => {
                    var line = &self.content.items[@intCast(self.y)];
                    if (line.items.len == 0) {
                        if (self.content.items.len == 1) {
                            return;
                        }
                        // delete line
                        line.deinit();
                        _ = self.content.orderedRemove(@intCast(self.y));
                        self.y -= 1;
                        // go to end of line before
                        self.x = @intCast(self.content.items[@intCast(self.y)].items.len);
                    } else {
                        if (self.x == 0) {
                            // TODO: UNHANDLED CASE. Remove line and add contents to line before
                            return;
                        }
                        // delete char we're on
                        _ = line.orderedRemove(@intCast(self.x - 1));
                        self.x -= 1;
                    }
                }, // delete (backspace)
                else => std.debug.print("CONTR = {d}\n\r", .{char}),
            }
        } else {
            try self.setChar(char);
        }
    }
};

var term = Terminal{};

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

    // std.os.SIG.WINCH // for resize signal
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

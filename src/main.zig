const std = @import("std");
const os = std.os;

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("ctype.h");
    @cInclude("sys/ioctl.h");
});

const terminalErr = error{ GETADDR, SETADDR, IOCTL };

const Terminal = struct {
    /// If the window should be open right now. Setting this to false will close the terminal.
    open: bool = false,
    orig_termios: c.termios = undefined,
    width: i32 = undefined,
    height: i32 = undefined,
    /// left is 1
    x: i32 = 1,
    /// top is 1
    y: i32 = 1,

    pub fn init(self: *Terminal) !void {
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

        self.open = true;
    }

    pub fn deinit(self: *Terminal) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("\x1b[?47l", .{}) catch unreachable; // restore saved screen

        // restore terminal mode from before
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.orig_termios);

        self.open = false;
    }

    /// Checks the current width and height of the terminal to adjust accordingly
    fn checkTerminalSize(self: *Terminal) !void {
        var w: c.winsize = undefined;
        if (c.ioctl(0, c.TIOCGWINSZ, &w) != 0)
            return terminalErr.IOCTL;
        self.width = w.ws_col;
        self.height = w.ws_row;
        if (self.width < self.x) self.x = self.width;
        if (self.height < self.y) self.y = self.height;
    }

    fn render(self: *Terminal) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[{d};{d}H", .{ self.y, self.x });
    }

    fn handleInput(self: *Terminal, buf: [3]u8) !void {
        const char = buf[0];
        if (char == 'q') {
            self.open = false;
            return;
        }
        if (c.iscntrl(char) == 0) {
            std.debug.print("CONTR = {u}\n\r", .{char});
        } else if (char == 27) {
            switch (buf[2]) {
                'A' => term.y = @max(1, @min(term.y - 1, term.height)),
                'B' => term.y = @max(1, @min(term.y + 1, term.height)),
                'C' => term.x = @max(1, @min(term.x + 1, term.width)),
                'D' => term.x = @max(1, @min(term.x - 1, term.width)),
                else => std.debug.print("UNKNWN = {u}\n\r", .{buf[2]}),
            }
        } else {
            std.debug.print("CHAR = {d}\n\r", .{char});
        }
    }
};

var term = Terminal{};

fn handleSigInt(_: c_int) callconv(.C) void {
    term.open = false;
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    term.checkTerminalSize() catch unreachable;
}

pub fn main() !void {
    try term.init();
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

    const stdout = std.io.getStdOut().writer();
    try stdout.print("PRESS 'q' TO EXIT\n\r", .{});

    const stdin = std.io.getStdIn().reader();
    while (term.open) {
        var buf: [3]u8 = undefined;
        const size = try stdin.read(&buf);
        if (size == 0) continue;
        try term.handleInput(buf);
        try term.render();
    }
}

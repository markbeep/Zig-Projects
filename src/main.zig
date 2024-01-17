const std = @import("std");
const os = std.os;

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("ctype.h");
});

const terminalErr = error{ GETADDR, SETADDR };

const Terminal = struct {
    open: bool = false,
    orig_termios: c.termios = undefined,

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

        self.open = true;
    }

    pub fn deinit(self: *Terminal) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("\x1b[?47l", .{}) catch unreachable; // restore saved screen

        // restore terminal mode from before
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &self.orig_termios);

        self.open = false;
    }
};

var term = Terminal{};

pub fn main() !void {
    try term.init();
    defer term.deinit();

    // std.os.SIG.WINCH // for resize signal
    try std.os.sigaction(os.SIG.INT, &os.Sigaction{
        .handler = .{ .handler = handleSigInt },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    const stdin = std.io.getStdIn().reader();
    while (term.open) {
        var buf: [3]u8 = undefined;
        const size = try stdin.read(&buf);
        if (size == 0) continue;
        const char = buf[0];
        if (char == 'q') break;
        if (c.iscntrl(char) == 0) {
            std.debug.print("INPUT = {u}\n\r", .{char});
        } else if (char == 27) {
            switch (buf[2]) {
                'A' => std.debug.print("UP\n\r", .{}),
                'B' => std.debug.print("DOWN\n\r", .{}),
                'C' => std.debug.print("RIGHT\n\r", .{}),
                'D' => std.debug.print("LEFT\n\r", .{}),
                else => std.debug.print("CONTR = {u}\n\r", .{buf[2]}),
            }
        } else {
            std.debug.print("CHAR = {d}\n\r", .{char});
        }
    }
}

fn handleSigInt(_: c_int) callconv(.C) void {
    term.open = false;
}

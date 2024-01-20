const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("ctype.h");
    @cInclude("sys/ioctl.h");
    @cInclude("stdlib.h");
});

const terminalErr = error{ GETADDR, SETADDR, IOCTL };

var orig_termios: c.termios = undefined;

pub const Terminal = struct {
    /// If the window should be open right now. Setting this to false will close the terminal.
    open: bool = false,
    width: i32 = undefined,
    height: i32 = undefined,
    /// The line to start displaying code at (for use with status bars, etc.)
    lineStart: i32 = 0,
    /// The amount of lines used for status bars and not for code
    statusLines: i32 = 0,
    /// The total line the cursor is currently on. Top-most line is 0.
    y: i32 = 0,
    /// The horizontal position the cursor is currently on. Left-most position is 0.
    x: i32 = 0,
    /// The scrolled line offset of the current view.
    scrollY: i32 = 0,
    scrollX: i32 = 0,
    content: std.ArrayList(std.ArrayList(u8)) = undefined,
    allocator: std.mem.Allocator = undefined,
    filepath: ?[]u8 = null,
    // If the user has requested to exit the program (i.e. using CTRL-C)
    exitState: bool = false,
    pendingChanges: bool = false,
    /// Banner shown on startup if no file is opened and nothing has been typed yet
    banner: bool = false,

    const lineNumberPadding = 4;
    const xOffset = lineNumberPadding + 3;
    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;

        // save screen and clear it
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[?1049h\x1b[2J", .{}); // open new screen, save and clear

        // enters terminal raw mode
        // source: https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
        if (c.tcgetattr(c.STDIN_FILENO, &orig_termios) != 0)
            return terminalErr.GETADDR;
        var raw = orig_termios;
        raw.c_iflag &= ~(@as(u32, c.IXON | c.ICRNL | c.ISTRIP));
        raw.c_oflag &= ~(@as(u32, c.OPOST));
        raw.c_lflag &= ~(@as(u32, c.ECHO | c.ICANON | c.ISIG | c.IEXTEN));
        raw.c_cflag |= @as(u32, c.CS8);
        raw.c_cc[c.VMIN] = 0;
        raw.c_cc[c.VTIME] = 1; // 1=100ms timeout
        if (c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw) != 0)
            return terminalErr.SETADDR;

        // TODO: not executed on errors/crash
        _ = c.atexit(Terminal.restoreTerminal);

        try self.checkTerminalSize();

        // check arguments
        const args = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, args);

        self.content = std.ArrayList(std.ArrayList(u8)).init(allocator);

        if (args.len >= 2) {
            self.filepath = try self.allocator.alloc(u8, args[1].len);
            @memcpy(self.filepath.?, args[1]);
            self.openFile(args[1]) catch |err| {
                if (err != std.fs.File.OpenError.FileNotFound) return err;
                self.banner = true;
            };
        } else {
            // initialize first line
            try self.content.append(std.ArrayList(u8).init(allocator));
            self.banner = true;
        }

        self.open = true;
    }

    fn restoreTerminal() callconv(.C) void {
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios);
    }

    pub fn deinit(self: *Self) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("\x1b[?1049l", .{}) catch unreachable; // restore saved screen

        // restore terminal mode from before
        Terminal.restoreTerminal();

        if (self.filepath) |path| {
            self.saveFile(path) catch unreachable;
            self.allocator.free(path);
        }

        for (self.content.items) |item| {
            item.deinit();
        }
        self.content.deinit();

        self.open = false;
    }

    /// Checks the current width and height of the terminal to adjust accordingly
    pub fn checkTerminalSize(self: *Self) !void {
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

    pub fn render(self: *Self) !void {
        self.statusLines = 0;
        const stdout = std.io.getStdOut().writer();
        var buf = std.io.bufferedWriter(stdout);
        var bw = buf.writer();

        try bw.print("\x1b[2J", .{}); // erase screen

        try self.renderStatusBar(bw);
        if (self.banner) {
            try self.renderBanner(bw);
        }

        // moves the screen accordingly if the cursor were to be placed outside
        if (self.y < self.scrollY) {
            self.scrollY = self.y;
        } else if (self.y > self.scrollY + self.height - self.statusLines - 1) {
            self.scrollY = self.y - self.height + self.statusLines + 1;
        }
        if (self.x < self.scrollX) {
            self.scrollX = self.x;
        } else if (self.x > self.scrollX + self.width - 1 - xOffset) {
            self.scrollX = self.x - self.width + 1 + xOffset;
        }

        try moveCursorBuffered(bw, 0, self.lineStart);
        for (self.content.items[@intCast(self.scrollY)..], 0..) |line, y| {
            if (y > self.height - self.statusLines - 1) break;
            try bw.print("\x1b[38;5;240m{d: >4} | \x1b[0m", .{y + @as(usize, @intCast(self.scrollY)) + 1}); // grey line number
            for (line.items, 0..) |char, x| {
                if (x > self.width - 1 - xOffset + self.scrollX) break;
                if (x < self.scrollX) continue;
                try bw.print("{u}", .{char});
            }
            try bw.print("\n\r", .{});
        }

        // move cursor to where cursor should be
        try moveCursorBuffered(bw, self.x + 1 + xOffset - self.scrollX, self.y + 1 - self.scrollY);

        try buf.flush();
    }

    fn renderStatusBar(self: *Self, bw: anytype) !void {
        self.statusLines += 1;
        try moveCursorBuffered(bw, 0, self.height);
        var spacesToPrint: usize = 25;
        if (self.exitState) {
            try bw.print("\x1b[1;43m    Tez  |  You have pending changes. 'C-c' to discard & exit", .{});
            spacesToPrint = 61;
        } else {
            try bw.print("\x1b[1;43m    Tez  |  'C-c' to exit", .{});
        }
        var rightSize: i32 = 5;
        if (self.x > 0) {
            rightSize += std.math.log10_int(@as(u32, @intCast(self.x + 1)));
        }
        if (self.y > 0) {
            rightSize += std.math.log10_int(@as(u32, @intCast(self.y + 1)));
        }
        // fill bottom line
        if (spacesToPrint < self.width - rightSize) {
            for ((spacesToPrint)..@intCast(self.width - rightSize)) |_| {
                try bw.print(" ", .{});
            }
        }
        try bw.print("{}:{}  \x1b[0m", .{ self.y + 1, self.x + 1 });
    }

    fn renderBanner(self: *Self, bw: anytype) !void {
        const actualHeight = self.height - self.statusLines - 1;
        const actualWidth = self.width - xOffset - 1;
        if (actualHeight < 8 or self.width < 27) return;
        const banner = [_][]const u8{
            "     _____",
            "    |_   _|__ ____",
            "      | |/ _ \\_  /",
            "      | |  __// /",
            "      |_|\\___/___|",
            " Lightweight text editor",
            "     Ctrl-C to exit",
        };
        const startY = @divFloor(actualHeight - @as(i32, @intCast(banner.len)), 2);
        const startX = @divFloor(actualWidth - 19, 2);
        if (startY <= 1 or startX <= 1) return;
        try moveCursorBuffered(bw, 0, startY);
        for (banner) |line| {
            for (0..@intCast(startX)) |_| {
                try bw.print(" ", .{});
            }
            try bw.print("{s}\n\r", .{line});
        }
    }

    fn setChar(self: *Self, char: u8) !void {
        self.pendingChanges = true;
        self.banner = false;
        switch (char) {
            '\n' => {
                // at the end of the line
                const maxX = self.content.items[@intCast(self.y)].items.len;
                self.y += 1;
                if (self.content.items.len <= self.y) {
                    try self.content.append(std.ArrayList(u8).init(self.allocator));
                } else {
                    try self.content.insert(@intCast(self.y), std.ArrayList(u8).init(self.allocator));
                }
                if (self.x != maxX) { // prepend line content to next line
                    const newLine = &self.content.items[@intCast(self.y)];
                    const line = &self.content.items[@intCast(self.y - 1)];
                    const slice = line.items[@intCast(self.x)..];
                    try newLine.insertSlice(0, slice);
                    try line.resize(@intCast(self.x));
                }
                self.x = 0;
            },
            else => {
                const line = &self.content.items[@intCast(self.y)];
                if (line.items.len <= self.x) {
                    try line.append(char);
                } else {
                    try line.insert(@intCast(self.x), char);
                }
                self.x += 1;
            },
        }
    }

    pub fn handleInput(self: *Self, buf: [3]u8) !void {
        const char = buf[0];
        if (char == 27) {
            const maxY: i32 = @intCast(self.content.items.len - 1);
            switch (buf[2]) {
                'A' => { // UP
                    if (self.y == 0) {
                        self.x = 0;
                    } else {
                        self.y = @max(0, self.y - 1);
                        const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                        self.x = @min(self.x, maxX);
                    }
                },
                'B' => { // DOWN
                    if (self.y == maxY) {
                        self.x = @intCast(self.content.items[@intCast(self.y)].items.len);
                    } else {
                        self.y += 1;
                        const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                        self.x = @min(self.x, maxX);
                    }
                },
                'C' => { // RIGHT
                    const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                    if (self.x == maxX and self.y != maxY) { // go to beginning of next line
                        self.y += 1;
                        self.x = 0;
                    } else {
                        self.x = @min(self.x + 1, maxX);
                    }
                },
                'D' => { // LEFT
                    if (self.x == 0 and self.y != 0) { // go to end of previous line
                        self.y -= 1;
                        const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
                        self.x = maxX;
                    } else {
                        self.x = @max(0, self.x - 1);
                    }
                },
                51 => {}, // DELETE
                170 => {}, // ESCAPE
                else => std.debug.print("UNKNWN = {d}\n\r", .{buf[2]}),
            }
        } else if (c.iscntrl(char) != 0) {
            switch (char) {
                13 => try self.setChar('\n'),
                127 => { // delete (backspace)
                    var line = &self.content.items[@intCast(self.y)];
                    if (line.items.len == 0 or self.x == 0) {
                        if (self.content.items.len == 1) {
                            return;
                        }
                        if (self.x == 0) {
                            var previousLine = &self.content.items[@intCast(self.y - 1)];
                            self.x = @intCast(previousLine.items.len);
                            try previousLine.appendSlice(line.items);
                        } else {
                            // go to end of line before
                            self.x = @intCast(self.content.items[@intCast(self.y)].items.len);
                        }
                        // delete line
                        line.deinit();
                        _ = self.content.orderedRemove(@intCast(self.y));
                        self.y -= 1;
                    } else {
                        // delete char we're on
                        _ = line.orderedRemove(@intCast(self.x - 1));
                        self.x -= 1;
                    }
                },
                3 => { // CTRL-C
                    if (self.exitState or !self.pendingChanges) {
                        self.open = false;
                        return;
                    }
                    self.exitState = true;
                },
                19 => {}, // CTRL-S
                21 => {}, // CTRL-U
                23 => {}, // CTRL-W
                else => std.debug.print("CONTR = {d}\n\r", .{char}),
            }
        } else {
            try self.setChar(char);
        }
    }

    fn openFile(self: *Self, path: []const u8) !void {
        // clear previously existing lines (incase we want to open a new file)
        for (self.content.items) |item| {
            item.deinit();
        }
        try self.content.resize(0);

        // add an initial first line
        // Handles the case of opening a new file since the next part will return an error
        try self.content.append(std.ArrayList(u8).init(self.allocator));

        var file: ?std.fs.File = null;
        if (std.fs.cwd().openFile(path, .{})) |f| {
            file = f;
        } else |err| {
            return err;
        }
        defer file.?.close();

        var buf_reader = std.io.bufferedReader(file.?.reader());
        var in_stream = buf_reader.reader();

        // TODO: only read the lines which we can see on the screen
        // max line size of 2KBs
        var lineno: u32 = 0;
        while (try in_stream.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2 << 10)) |line| {
            defer self.allocator.free(line);
            if (lineno > 0) {
                try self.content.append(std.ArrayList(u8).init(self.allocator));
            }
            lineno += 1;
            var list = &self.content.items[self.content.items.len - 1];
            try list.appendSlice(line);
        }
    }

    fn saveFile(self: *Self, path: []const u8) !void {
        // create new file if non-existent
        var file: std.fs.File = undefined;
        const fileUnion = std.fs.cwd().openFile(path, .{ .mode = std.fs.File.OpenMode.write_only });
        if (fileUnion) |f| {
            file = f;
        } else |err| {
            if (err != std.fs.File.OpenError.FileNotFound) return err;
            file = try std.fs.cwd().createFile(path, .{});
        }

        defer file.close();

        var buf_writer = std.io.bufferedWriter(file.writer());
        var stream = buf_writer.writer();

        for (self.content.items) |line| {
            _ = try stream.write(line.items);
            try stream.writeByte('\n');
        }
        try buf_writer.flush();
    }
};

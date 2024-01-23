const TEZ_VERSION = "v0.0.2";

const std = @import("std");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("ctype.h");
    @cInclude("sys/ioctl.h");
    @cInclude("stdlib.h");
});

const TerminalError = error{ TerminalNotSetup, GETADDR, SETADDR, IOCTL };

var orig_termios: c.termios = undefined;

pub const Terminal = struct {
    const Self = @This();
    /// If the window should be open right now. Setting this to false will close the terminal.
    open: bool = false,
    width: i32 = undefined,
    height: i32 = undefined,
    /// The line to start displaying code at (for use with status bars, etc.)
    lineStart: i32 = 0,
    /// The amount of lines used for status bars and not for code
    statusLines: i32 = 0,
    /// The total line the cursor is currently on. Top-most line is 0.
    /// y can at most be the number of lines minus one. If there are 3 lines, max(y)=2.
    y: i32 = 0,
    /// The horizontal position the cursor is currently on. Left-most position is 0.
    /// A line with 4 elements, x can be in the inclusive range [0, 4]. x=4 won't contain
    /// a character though.
    x: i32 = 0,
    /// The x-coordinate we were at before jumping somewhere
    lastX: i32 = 0,
    /// The scrolled line offset of the current view.
    scrollY: i32 = 0,
    scrollX: i32 = 0,
    content: std.ArrayList(std.ArrayList(u8)) = undefined,
    allocator: std.mem.Allocator = undefined,
    filepath: ?[]u8 = null,
    /// If the user has requested to exit the program (i.e. using CTRL-C)
    exitState: bool = false,
    pendingChanges: bool = false,
    /// Banner shown on startup if no file is opened and nothing has been typed yet
    banner: bool = false,
    // TODO: Look into how this can be fixed so it works in all terminals.
    /// For keys like DELETE which add an extra character afterwards.
    ignoreChars: usize = 0,
    isTerminalSetup: bool = false,
    debugMode: bool = false,

    const lineNumberPadding = 4;
    const xOffset = lineNumberPadding + 2;

    const colors = struct {
        // TODO: involve the background without a massive performance drop
        const bg = "\x1b[48;5;234m";
        const text = "";
        const offset = "\x1b[38;5;240m";
        const zero = "\x1b[0m";
        const status = "\x1b[1;48;5;214m";
    };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var term = Self{};

        term.allocator = allocator;

        // check arguments
        const args = try std.process.argsAlloc(term.allocator);
        defer std.process.argsFree(term.allocator, args);

        term.content = std.ArrayList(std.ArrayList(u8)).init(allocator);

        if (args.len >= 2) {
            term.filepath = try term.allocator.alloc(u8, args[1].len);
            @memcpy(term.filepath.?, args[1]);
            term.openFile(args[1]) catch |err| {
                if (err != std.fs.File.OpenError.FileNotFound) return err;
                term.banner = true;
            };
        } else {
            // initialize first line
            try term.content.append(std.ArrayList(u8).init(allocator));
            term.banner = true;
        }

        term.open = true;
        return term;
    }

    pub fn setupTerminal(self: *Self) !void {
        // save screen and clear it
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\x1b[?1049h\x1b[2J", .{}); // open new screen, save and clear

        // enters terminal raw mode
        // source: https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
        if (c.tcgetattr(c.STDIN_FILENO, &orig_termios) != 0)
            return TerminalError.GETADDR;
        var raw = orig_termios;
        raw.c_iflag &= ~(@as(u32, c.IXON | c.ICRNL | c.ISTRIP));
        raw.c_oflag &= ~(@as(u32, c.OPOST));
        raw.c_lflag &= ~(@as(u32, c.ECHO | c.ICANON | c.ISIG | c.IEXTEN));
        raw.c_cflag |= @as(u32, c.CS8);
        raw.c_cc[c.VMIN] = 0;
        raw.c_cc[c.VTIME] = 1; // 1=100ms timeout
        if (c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw) != 0)
            return TerminalError.SETADDR;

        try self.checkTerminalSize();
        self.isTerminalSetup = true;
    }

    pub fn restoreTerminal(self: *Self) void {
        if (!self.isTerminalSetup) return;
        const stdout = std.io.getStdOut().writer();
        stdout.print("\x1b[?1049l", .{}) catch unreachable; // restore saved screen
        // restore terminal mode from before
        _ = c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios);
    }

    /// Listens for keypresses and handles them. This function is blocking.
    pub fn listenForInput(self: *Self) !void {
        if (!self.isTerminalSetup) {
            return TerminalError.TerminalNotSetup;
        }
        const stdin = std.io.getStdIn().reader();
        while (self.open) {
            var buf: [3]u8 = undefined;
            const size = try stdin.read(&buf);
            if (size == 0) continue;
            try self.handleInput(buf);
            try self.render();
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.filepath) |path| {
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
            return TerminalError.IOCTL;
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

        if (!self.debugMode) {
            try bw.print("\x1b[2J", .{}); // erase screen
        }

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
            try bw.print("{s}{d: >4}  \x1b[0m", .{ colors.offset, y + @as(usize, @intCast(self.scrollY)) + 1 }); // grey line number
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
            try bw.print("{s}    Tez  |  You have pending changes. 'C-c' to discard & exit", .{colors.status});
            spacesToPrint = 61;
        } else {
            try bw.print("{s}    Tez  |  'C-c' to exit", .{colors.status});
        }
        var rightSize: i32 = 6;
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
        try bw.print("{}:{}   \x1b[0m", .{ self.y + 1, self.x + 1 });
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
            "         " ++ TEZ_VERSION,
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
        self.lastX = self.x;
    }

    pub fn handleInput(self: *Self, buf: [3]u8) !void {
        const char = buf[0];
        if (self.ignoreChars > 0) {
            self.ignoreChars -= 1;
            return;
        }
        if (char == 27) {
            switch (buf[2]) {
                'A' => self.moveUp(1), // UP
                'B' => self.moveDown(1), // DOWN
                'C' => self.moveRight(1), // RIGHT
                'D' => self.moveLeft(1), // LEFT
                49 => { // CTRL SHIFT D
                    self.debugMode = !self.debugMode;
                    self.ignoreChars = 2;
                },
                51 => { // DELETE (del)
                    // if we're at the very last character, don't delete
                    self.ignoreChars = 1;
                    try self.deleteRight(1);
                },
                70 => self.x = self.getMaxX(self.y), // END
                72 => self.x = 0, // HOME
                170 => {}, // ESCAPE
                else => std.debug.print("UNKNWN = {d}\n\r", .{buf[2]}),
            }
        } else if (c.iscntrl(char) != 0) {
            switch (char) {
                13 => try self.setChar('\n'),
                127 => try self.deleteLeft(1), // delete (backspace)
                3 => { // CTRL-C
                    if (self.exitState or !self.pendingChanges) {
                        self.open = false;
                        return;
                    }
                    self.exitState = true;
                },
                19 => {
                    if (self.filepath) |path| {
                        try self.saveFile(path);
                        self.exitState = false;
                        self.pendingChanges = false;
                    }
                }, // CTRL-S
                4 => self.moveDown(@intCast(@divFloor(self.height, 2))), // CTRL-D: go down half the page
                21 => self.moveUp(@intCast(@divFloor(self.height, 2))), // CTRL-U: go up half the page
                23 => {}, // CTRL-W
                else => std.debug.print("CONTR = {d}\n\r", .{char}),
            }
        } else {
            try self.setChar(char);
        }
    }

    // #############################
    //
    // GENERAL FUNCTIONS
    //
    // #############################

    pub fn moveUp(self: *Self, times: u32) void {
        if (self.y == 0) {
            self.x = 0;
            self.lastX = self.x;
        } else {
            self.y = @max(0, self.y - @as(i32, @intCast(times)));
            const maxX: i32 = @intCast(self.content.items[@intCast(self.y)].items.len);
            self.x = @min(self.lastX, maxX);
        }
    }

    pub fn moveDown(self: *Self, times: u32) void {
        if (self.y == self.getMaxY()) {
            self.x = self.getMaxX(self.y);
            self.lastX = self.x;
        } else {
            self.y = @min(self.y + @as(i32, @intCast(times)), self.getMaxY());
            self.x = @min(self.lastX, self.getMaxX(self.y));
        }
    }

    pub fn moveRight(self: *Self, times: u32) void {
        const maxY: i32 = @intCast(self.content.items.len - 1);
        for (0..times) |_| {
            const maxX = self.getMaxX(self.y);
            if (self.x == maxX and self.y != maxY) { // go to beginning of next line
                self.y += 1;
                self.x = 0;
            } else {
                self.x = @min(self.x + 1, maxX);
            }
            self.lastX = self.x;
        }
    }

    pub fn moveLeft(self: *Self, times: u32) void {
        for (0..times) |_| {
            if (self.x == 0 and self.y != 0) { // go to end of previous line
                self.y -= 1;
                self.x = self.getMaxX(self.y);
            } else {
                self.x = @max(0, self.x - 1);
            }
            self.lastX = self.x;
        }
    }

    /// Deletes one character to the left
    pub fn deleteLeft(self: *Self, times: u32) !void {
        self.pendingChanges = self.pendingChanges or times > 0;
        for (0..times) |_| {
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
                    self.x = self.getMaxX(self.y);
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
        }
    }

    pub fn deleteRight(self: *Self, times: u32) !void {
        for (0..times) |_| {
            if (self.y != self.getMaxY() or self.x != self.getMaxX(self.y)) {
                self.moveRight(1);
                try self.deleteLeft(1);
            }
        }
    }

    pub fn getMaxY(self: *Self) i32 {
        return @intCast(self.content.items.len - 1);
    }

    pub fn getMaxX(self: *Self, y: i32) i32 {
        return @intCast(self.content.items[@intCast(y)].items.len);
    }

    pub fn openFile(self: *Self, path: []const u8) !void {
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

    pub fn saveFile(self: *Self, path: []const u8) !void {
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

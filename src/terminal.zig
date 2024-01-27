const std = @import("std");
const os = std.os;
const ascii = std.ascii;
const unicode = std.unicode;

const TEZ_VERSION = "0.0.3";

const TerminalError = error{ TerminalNotSetup, IoctlFailed };

const TerminalCallback = *const fn (*Terminal) void;
const MapKV = struct { []const u8, TerminalCallback };
const ControlKV = struct { u32, TerminalCallback };

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

const keymappings = std.ComptimeStringMap(TerminalCallback, [_]MapKV{
    .{ "[A", arrowUp },
    .{ "[B", arrowDown },
    .{ "[C", arrowRight },
    .{ "[D", arrowLeft },
    .{ "[H", home },
    .{ "[F", end },
    .{ "[3~", delete },
    .{ "[24~", insert },
    .{ "[5~", pgUp },
    .{ "[6~", pgDown },
    .{ "", escape },
    .{ "[100;6u", c_s_d },

    // control keys
    .{ "a", noop },
    .{ "b", noop },
    .{ "c", c_c },
    .{ "d", c_d },
    .{ "e", noop },
    .{ "f", noop },
    .{ "g", noop },
    .{ "h", noop },
    .{ "i", noop },
    .{ "j", noop },
    .{ "k", noop },
    .{ "l", noop },
    .{ "m", enter }, // equal to 'enter'
    .{ "n", noop },
    .{ "o", noop },
    .{ "p", noop },
    .{ "q", noop },
    .{ "r", noop },
    .{ "s", c_s },
    .{ "t", noop },
    .{ "u", c_u },
    .{ "v", noop },
    .{ "w", c_w },
    .{ "x", noop },
    .{ "y", noop },
    .{ "z", noop },
    .{ "\x7f", backspace }, // equal to '127'
});

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
    debugMode: bool = false,
    cursorMode: CursorMode = CursorMode.blinkingBar,
    errorMessage: ?[]const u8 = "Sample error message",

    original_termios: ?os.termios = null,

    const lineNumberPadding = 4;
    const xOffset = lineNumberPadding + 2;

    const colors = struct {
        const bg = "\x1b[48;5;234m";
        const text = "\x1b[97m";
        const offset = "\x1b[38;5;240m";
        const statusText = "\x1b[38;5;234m"; // textcolor = bg color
        const status = "\x1b[48;5;214m";
        const zero = "\x1b[0m";
        const bold = "\x1b[1m";
        const underline = "\x1b[4m";
    };

    /// Initialize a terminal instance.
    ///
    /// **Note:** This does not set up the terminal.
    /// Use `terminal.setupTerminal()` for that.
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

    pub fn setupTerminal(self: *Self) !void {
        var tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = std.fs.File.OpenMode.read_write });
        defer tty.close();

        // save the current terminal state
        self.original_termios = try os.tcgetattr(tty.handle);
        var raw = self.original_termios.?;

        // enters terminal raw mode
        // source: https://zig.news/lhp/want-to-create-a-tui-application-the-basics-of-uncooked-terminal-io-17gm
        // alt source: "Raw mode" section here https://man7.org/linux/man-pages/man3/termios.3.html
        const flags = os.linux;
        // ECHO     Don't echo input characters.
        // ECHONL   Don't echo newline character.
        // ICANON   Disabele canonical mode. Read inputs byte-wise instead of line-wise.
        // ISIG     Disable signals for Ctrl-C (SIGINT) and Ctrl-Z (SIGTSTP).
        // EXTEN    Disable input preprocessing. This allows us to handle Ctrl-V.
        raw.lflag &= ~(@as(os.system.tcflag_t, flags.ECHO | flags.ECHONL | flags.ICANON | flags.ISIG | flags.IEXTEN));
        // IXON     Disable software control flow. This allows us to handle Ctrl-S and Ctrl-Q.
        // ICRNL    Disable converting carriage returns to newlines. Allows us to handle Ctrl-J and Ctrl-M.
        // IGNBRK   Get BREAK as an input
        // INLCR    Disables translating NL to CR
        // IGNCR    Does not ignore CR
        // INPCK    Disable parity checking.
        // ISTRIP   Disable stripping the 8th bit of characters.
        raw.iflag &= ~(@as(
            os.system.tcflag_t,
            flags.IXON | flags.ICRNL | flags.BRKINT | flags.INLCR | flags.IGNCR | flags.INPCK | flags.ISTRIP,
        ));
        // OPOST    Disable implementation-defined output processing.
        raw.oflag &= ~(@as(os.system.tcflag_t, flags.OPOST));
        // CSIZE    Character size mask.
        // PARENB   Disable parity generation on output and parity checking for input.
        // CS8      Ensures characters to be 8 bits.
        raw.cflag &= ~(@as(os.system.tcflag_t, flags.CSIZE | flags.PARENB));
        raw.cflag |= @as(os.system.tcflag_t, flags.CS8);

        // Timeout in deciseconds (100ms)
        raw.cc[os.linux.V.TIME] = 1;
        // Minimum number of characters for read
        raw.cc[os.linux.V.MIN] = 0;

        try os.tcsetattr(tty.handle, .FLUSH, raw);

        const stdout = std.io.getStdOut().writer();
        var buf = std.io.bufferedWriter(stdout);
        var bw = buf.writer();

        try bw.print("\x1b[s", .{}); // save cursor position
        try bw.print("\x1b[?47h", .{}); // save screen
        try bw.print("\x1b[?1049h", .{}); // enable alternative buffer
        try buf.flush();

        try self.checkTerminalSize();
    }

    pub fn restoreTerminal(self: *Self) void {
        if (self.original_termios == null) return;
        var tty = std.fs.cwd().openFile(
            "/dev/tty",
            .{ .mode = std.fs.File.OpenMode.read_write },
        ) catch unreachable;
        defer tty.close();

        os.tcsetattr(tty.handle, .FLUSH, self.original_termios.?) catch unreachable;

        const stdout = std.io.getStdOut().writer();
        var buf = std.io.bufferedWriter(stdout);
        var bw = buf.writer();

        bw.print("\x1b[?1049l", .{}) catch unreachable; // disable alternative buffer
        bw.print("\x1b[?47l", .{}) catch unreachable; // restore screen
        bw.print("\x1b[{d} q", .{@intFromEnum(CursorMode.blinkingBlock)}) catch unreachable; // set cursor back to blinking block
        bw.print("\x1b[u", .{}) catch unreachable; // restore cursor position

        buf.flush() catch unreachable;
    }

    /// Listens for keypresses and handles them. This function is blocking.
    pub fn listenForInput(self: *Self) !void {
        if (self.original_termios == null) {
            return TerminalError.TerminalNotSetup;
        }
        var tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = std.fs.File.OpenMode.read_write });
        defer tty.close();
        while (self.open) {
            var buf: [8]u8 = undefined;
            const size = try tty.read(&buf);
            if (size == 0) continue;
            try self.handleInput(buf, size);
            try self.render();
        }
    }

    pub fn handleInput(self: *Self, buf: [8]u8, size: usize) !void {
        const char = buf[0];

        var func: ?TerminalCallback = null;
        if (char == 0x1b) { // escape sequence
            func = keymappings.get(buf[1..size]);
        } else if (ascii.isControl(char)) {
            if (char == 127) {
                func = keymappings.get(buf[0..1]);
            } else {
                const asciiChar = [1]u8{buf[0] + 96};
                func = keymappings.get(&asciiChar);
            }
        }
        if (func) |f| {
            f(self);
            return;
        }
        if (self.debugMode) {
            std.debug.print("MAPPING = '{s}' | {any}\n\r", .{ buf[0..size], buf[0..size] });
        }

        try self.setChars(buf[0..size]);
    }

    fn setChars(self: *Self, chars: []const u8) !void {
        self.pendingChanges = true;
        self.banner = false;
        self.exitState = false;

        // buffered inserts. insert up to a newline character
        // Allows for more efficient insertions of multiple characters (like pasting)
        var start: usize = 0;
        for (chars, 0..) |c, i| {
            if (c == '\n') {
                if (start < i) {
                    try self.insertSlice(chars[start..i]);
                }
                try self.insertNewline();
                start = i + 1;
            }
        }
        if (start < chars.len) {
            try self.insertSlice(chars[start..]);
        }
        self.lastX = self.x;
    }

    fn insertNewline(self: *Self) !void {
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
    }

    fn insertSlice(self: *Self, chars: []const u8) !void {
        const line = &self.content.items[@intCast(self.y)];
        if (line.items.len <= self.x) {
            try line.appendSlice(chars);
        } else {
            try line.insertSlice(@intCast(self.x), chars);
        }
        self.x += @intCast(chars.len);
    }

    /// Checks the current width and height of the terminal to adjust accordingly
    pub fn checkTerminalSize(self: *Self) !void {
        var w: os.linux.winsize = undefined;
        if (os.system.ioctl(0, os.linux.T.IOCGWINSZ, @intFromPtr(&w)) != 0) {
            return TerminalError.IoctlFailed;
        }
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

        try bw.print("{s}", .{colors.bg}); // before erase to fill whole terminal with color
        if (!self.debugMode) {
            try bw.print("\x1b[2J", .{}); // erase screen
            try bw.print("\x1b[?25l", .{}); // hide cursor to avoid flickering
        }
        try bw.print("\x1b[{d} q", .{@intFromEnum(self.cursorMode)}); // changes how the cursor looks

        try self.renderStatusBar(bw);
        if (self.errorMessage) |msg| {
            const errMsg = try std.fmt.allocPrint(self.allocator, "Err: {s}", .{msg});
            defer self.allocator.free(errMsg);
            try self.renderTextBar(self.height - self.statusLines, errMsg, bw);
        }
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
            try bw.print("{s}{s}{d: >4}  {s}{s}", .{
                colors.offset,
                colors.bg,
                y + @as(usize, @intCast(self.scrollY)) + 1,
                colors.zero,
                colors.bg,
            }); // grey line number
            for (line.items, 0..) |char, x| {
                if (x > self.width - 1 - xOffset + self.scrollX) break;
                if (x < self.scrollX) continue;
                try bw.print("{u}", .{char});
            }
            try bw.print("\n\r", .{});
        }
        try bw.print("{s}", .{colors.zero});

        // move cursor to where cursor should be
        try moveCursorBuffered(bw, self.x + 1 + xOffset - self.scrollX, self.y + 1 - self.scrollY);

        try bw.print("\x1b[?25h", .{}); // show cursor again

        try buf.flush();
    }

    fn renderStatusBar(self: *Self, bw: anytype) !void {
        self.statusLines += 1;
        try moveCursorBuffered(bw, 0, self.height);
        try bw.print("{s}{s}\x1b[K", .{ colors.status, colors.bold });
        if (self.exitState) {
            try bw.print("{s}    Tez  |  You have pending changes. 'C-c' to discard & exit", .{colors.statusText});
        } else {
            try bw.print("{s}    Tez  |  'C-c' to exit", .{colors.statusText});
        }
        var rightSize: i32 = 6;
        if (self.x > 0) {
            rightSize += std.math.log10_int(@as(u32, @intCast(self.x + 1)));
        }
        if (self.y > 0) {
            rightSize += std.math.log10_int(@as(u32, @intCast(self.y + 1)));
        }
        try moveCursorBuffered(bw, self.width - rightSize, self.height);
        try bw.print("{}:{}   \x1b[0m", .{ self.y + 1, self.x + 1 });
    }

    fn renderTextBar(self: *Self, y: i32, text: []const u8, bw: anytype) !void {
        self.statusLines += 1;
        try moveCursorBuffered(bw, 0, y);
        try bw.print("{s}\x1b[K", .{colors.status});
        try bw.print("{s}    {s}{s}", .{ colors.statusText, text, colors.zero });
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
            "         v" ++ TEZ_VERSION,
        };
        const startY = @divFloor(actualHeight - @as(i32, @intCast(banner.len)), 2);
        const startX = @divFloor(actualWidth - 19, 2);
        if (startY <= 1 or startX <= 1) return;
        try moveCursorBuffered(bw, 0, startY);
        try bw.print("{s}{s}{s}", .{ colors.text, colors.bg, colors.bold });
        for (banner) |line| {
            for (0..@intCast(startX)) |_| {
                try bw.print(" ", .{});
            }
            try bw.print("{s}\n\r", .{line});
        }
        try bw.print("{s}", .{colors.zero});
    }

    // #############################
    //
    // GENERAL FUNCTIONS (assignable to keybinds)
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
                if (self.y == 0) {
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
        while (try in_stream.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 2 << 10)) |line| : (lineno += 1) {
            defer self.allocator.free(line);
            if (lineno > 0) {
                try self.content.append(std.ArrayList(u8).init(self.allocator));
            }
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

// Arrows

fn arrowUp(self: *Terminal) void {
    self.moveUp(1);
}
fn arrowDown(self: *Terminal) void {
    self.moveDown(1);
}
fn arrowRight(self: *Terminal) void {
    self.moveRight(1);
}
fn arrowLeft(self: *Terminal) void {
    self.moveLeft(1);
}

// General keys

fn home(self: *Terminal) void {
    self.x = 0;
}
fn end(self: *Terminal) void {
    self.x = self.getMaxX(self.y);
}
fn delete(self: *Terminal) void {
    // if we're at the very last character, don't delete
    self.deleteRight(1) catch return;
}
fn insert(self: *Terminal) void {
    _ = self; // autofix
}
fn backspace(self: *Terminal) void {
    self.deleteLeft(1) catch return;
}
fn pgUp(self: *Terminal) void {
    _ = self; // autofix
}
fn pgDown(self: *Terminal) void {
    _ = self; // autofix
}
fn escape(self: *Terminal) void {
    self.exitState = false;
}
fn enter(self: *Terminal) void {
    self.setChars("\n") catch return;
}

// Control keys

fn c_c(self: *Terminal) void {
    if (self.exitState or !self.pendingChanges) {
        self.open = false;
        return;
    }
    self.exitState = true;
}
fn c_s(self: *Terminal) void {
    if (self.filepath) |path| {
        self.saveFile(path) catch return;
        self.exitState = false;
        self.pendingChanges = false;
    }
}
fn c_d(self: *Terminal) void {
    self.moveDown(@intCast(@divFloor(self.height, 2)));
}
fn c_u(self: *Terminal) void {
    self.moveUp(@intCast(@divFloor(self.height, 2)));
}
fn c_w(self: *Terminal) void {
    _ = self; // autofix
}

// Control Shift keys

fn c_s_d(self: *Terminal) void {
    self.debugMode = !self.debugMode;
}

fn noop(_: *Terminal) void {}

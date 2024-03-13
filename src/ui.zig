const core = @import("core.zig");
const std = @import("std");
const os = std.os;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const key_mappings = @import("key_mapping.zig");
const logger = @import("log.zig").logger;

/// Type of cursor to use.
///
/// More information: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h4-Functions-using-CSI-_-ordered-by-the-final-character-lparen-s-rparen:CSI-Ps-SP-q.1D81
const CursorMode = enum(u4) {
    blinking_block = 1,
    steady_block = 2,
    blinking_underline = 3,
    steady_underline = 4,
    blinking_bar = 5,
    steady_bar = 6,
};

const EditMode = enum(u2) {
    normal,
    insert,
    visual,
    /// Allows for a command to be entered (like :q)
    command,
};

const TerminalOptions = struct {
    initial_filepath: ?[]const u8 = null,
    setup_terminal: bool = false,
};

pub const Terminal = struct {
    const Self = @This();

    edit_mode: EditMode = EditMode.normal,
    editor: core.CoreEditor,
    open: bool,
    command_buffer: GapBuffer(u8),
    options: ?TerminalOptions,
    original_termios: ?os.termios,
    allocator: Allocator,

    /// Initializes a terminal instance and initializes the terminal
    pub fn init(allocator: Allocator, options: ?TerminalOptions) !Self {
        const editor = try core.CoreEditor.init(allocator);

        var self = Self{
            .editor = editor,
            .open = true,
            .command_buffer = GapBuffer(u8).init(allocator),
            .options = options,
            .original_termios = null,
            .allocator = allocator,
        };

        if (options) |opt| {
            if (opt.setup_terminal) {
                try self.setupTerminal();
            }
        }

        return self;
    }

    /// Adds the correct styling and options to the terminal
    fn setupTerminal(self: *Self) !void {
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

        self.handleTerminalResize();
    }

    /// Restores the terminal styling and options
    fn restoreTerminal(self: Self) void {
        if (self.original_termios == null) return;
        const tty = std.fs.cwd().openFile(
            "/dev/tty",
            .{ .mode = std.fs.File.OpenMode.read_write },
        ) catch null;

        if (tty) |t| {
            defer t.close();
            os.tcsetattr(t.handle, .FLUSH, self.original_termios.?) catch {};
        }

        const stdout = std.io.getStdOut().writer();
        var buf = std.io.bufferedWriter(stdout);
        var bw = buf.writer();

        bw.print("\x1b[?1049l", .{}) catch {}; // disable alternative buffer
        bw.print("\x1b[?47l", .{}) catch {}; // restore screen
        // TODO: How to reset cursor mode to what it was before?
        bw.print("\x1b[{d} q", .{@intFromEnum(CursorMode.blinking_block)}) catch {}; // set cursor back to blinking block
        bw.print("\x1b[u", .{}) catch {}; // restore cursor position

        buf.flush() catch {};
    }

    /// Handles updating the display to adjust to the new terminal size
    pub fn handleTerminalResize(self: *Self) void {
        self.render();
    }

    /// Restores the terminal
    pub fn deinit(self: Self) void {
        if (self.options) |opt| {
            if (opt.setup_terminal) {
                self.restoreTerminal();
            }
        }

        self.editor.deinit();
        self.command_buffer.deinit();
    }

    pub fn render(self: Self) void {
        _ = self;
    }

    fn executeCommand(self: *Self, command: []const u8) void {
        if (command[0] == 'q') {
            self.open = false;
        }
    }

    pub fn handleInput(self: *Self, buf: [8]u8, size: usize) !void {
        if (size == 0) return;

        const input = key_mappings.parseInput(buf, size) catch {
            return;
        };

        switch (self.edit_mode) {
            .normal => {
                switch (buf[0]) { // TODO: support longer sequences
                    ':' => {
                        self.edit_mode = .command;
                        self.command_buffer.deleteAll();
                    },
                    'i' => {
                        self.edit_mode = .insert;
                    },
                    else => @panic("unimplemented"),
                }
            },
            .insert => {
                // TODO: Add way to exit insert mode with escape
                if (input.is_print) {
                    try self.editor.addChars(buf[0..size]);
                } else {
                    switch (input.key_code) {
                        .escape => self.edit_mode = .normal,
                        else => @panic("unimplemented"),
                    }
                }
            },
            .command => {
                switch (input.key_code) {
                    .enter => {
                        if (self.command_buffer.len > 0) {
                            const command = try self.command_buffer.getOwnedSlice();
                            defer self.allocator.free(command);
                            self.executeCommand(command);
                        }
                        self.edit_mode = .normal;
                    },
                    .printable => {
                        try self.command_buffer.insertSlice(buf[0..size]);
                    },
                    else => @panic("unimplemented"),
                }
            },
            else => @panic("unimplemented"),
        }
    }
};

test "init and quit ui" {
    var term = try Terminal.init(testing.allocator, .{ .setup_terminal = false });
    defer term.deinit();
    try testing.expectEqual(EditMode.normal, term.edit_mode);
    try testing.expect(term.open);
    const inp_1 = [8]u8{ ':', 0, 0, 0, 0, 0, 0, 0 };
    const inp_2 = [8]u8{ 'q', 0, 0, 0, 0, 0, 0, 0 };
    const enter = [8]u8{ '\x0d', 0, 0, 0, 0, 0, 0, 0 };
    try term.handleInput(inp_1, 1);
    try term.handleInput(inp_2, 1);
    try term.handleInput(enter, 1);
    try testing.expect(!term.open);
}

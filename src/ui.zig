const core = @import("core.zig");
const std = @import("std");
const os = std.os;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;

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
    setup_terminal: bool = true,
};

pub const Terminal = struct {
    const Self = @This();

    edit_mode: EditMode = EditMode.normal,
    editor: core.CoreEditor,
    open: bool,
    command_buffer: GapBuffer(u8),
    options: ?TerminalOptions,

    /// Initializes a terminal instance and initializes the terminal
    pub fn init(allocator: Allocator, options: ?TerminalOptions) !Self {
        const editor = try core.CoreEditor.init(allocator);

        const self = Self{
            .editor = editor,
            .open = true,
            .command_buffer = GapBuffer(u8).init(allocator),
            .options = options,
        };

        if (options) |opt| {
            if (opt.setup_terminal) {
                self.setupTerminal();
            }
        }

        return self;
    }

    /// Manually adds the correct styling to the terminal.
    /// Should not be called manually unless `setup_terminal`
    /// was set to `false` on initialization.
    pub fn setupTerminal(self: Self) void {
        _ = self;
    }

    /// Manually restores the terminal.
    /// Should not be called manually unless `setup_terminal`
    /// was set to `false` on initialization.
    pub fn restoreTerminal(self: Self) void {
        _ = self;
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

    pub fn handleInput(self: *Self, buf: [8]u8) !void {
        // FIXME: very rough input handler which crashes if anything other than ':q' is inserted
        switch (self.edit_mode) {
            .normal => {
                switch (buf[0]) {
                    ':' => {
                        self.edit_mode = .command;
                        self.command_buffer.deleteAll();
                    },
                    else => unreachable,
                }
            },
            .command => {
                switch (buf[0]) {
                    'q' => {
                        self.open = false;
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
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
    try term.handleInput(inp_1);
    try term.handleInput(inp_2);
    try testing.expect(!term.open);
}

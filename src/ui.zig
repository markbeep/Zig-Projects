const core = @import("core.zig");

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
};

const TerminalOptions = struct {
    filepath: []const u8,
};

pub const Terminal = struct {
    edit_mode: EditMode = EditMode.normal,
};

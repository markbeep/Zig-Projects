const std = @import("std");
const ascii = std.ascii;

pub const ParseError = error{
    invalid_character,
    unhandled_case,
};

pub const KeyCode = enum {
    printable,

    arrow_up,
    arrow_down,
    arrow_right,
    arrow_left,
    home,
    end,
    delete,
    insert,
    page_up,
    page_down,
    escape,
    backspace,
};

pub const Input = struct {
    key_code: KeyCode,
    is_print: bool = false,
    is_control: bool = false,
    value: []const u8,
};

const MapKV = struct { []const u8, KeyCode };

const keymappings = std.ComptimeStringMap(KeyCode, [_]MapKV{
    .{ "[A", .arrow_up },
    .{ "[B", .arrow_down },
    .{ "[C", .arrow_right },
    .{ "[D", .arrow_left },
    .{ "[H", .home },
    .{ "[F", .end },
    .{ "[3~", .delete },
    .{ "[24~", .insert },
    .{ "[5~", .page_up },
    .{ "[6~", .page_down },
    .{ "", .escape },
    .{ "\x7f", .backspace }, // equal to '127'
});

pub fn parseInput(buf: [8]u8, size: usize) ParseError!Input {
    if (size == 1) {
        if (ascii.isPrint(buf[0])) {
            return Input{
                .is_print = true,
                .key_code = .printable,
                .value = buf[0..1],
            };
        } else return ParseError.invalid_character;
    }
    return ParseError.unhandled_case;
}

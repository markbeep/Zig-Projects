const std = @import("std");
const ascii = std.ascii;
const unicode = std.unicode;
const testing = std.testing;

pub const ParseError = error{
    invalid_character,
    unhandled_escape,
    unhandled_case,
};

pub const KeyCode = enum {
    printable,
    enter,

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
    /// Escape sequence
    is_escape_seq: bool = false,
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

    // control keys
    .{ "\x0d", .enter },
    .{ "\x7f", .backspace }, // equal to '127'
});

pub fn parseInput(buf: [8]u8, size: usize) ParseError!Input {
    if (buf[0] == '\n') {
        return Input{
            .is_print = true,
            .key_code = .enter,
        };
    } else if (ascii.isPrint(buf[0])) { // single printable ascii chars
        return Input{
            .is_print = true,
            .key_code = .printable,
        };
    } else if (buf[0] == 0x1b) { // escape sequence
        const key_code = keymappings.get(buf[1..size]);
        if (key_code) |k| {
            return Input{
                .is_escape_seq = true,
                .key_code = k,
            };
        } else {
            return ParseError.unhandled_escape;
        }
    } else if (ascii.isControl(buf[0])) {
        const key_code = keymappings.get(buf[0..1]);
        if (key_code) |k| {
            return Input{
                .is_control = true,
                .key_code = k,
            };
        } else {
            return ParseError.unhandled_escape;
        }
    }

    if (unicode.utf8ValidateSlice(buf[0..size])) {
        return Input{
            .is_print = true,
            .key_code = .printable,
        };
    }

    return ParseError.unhandled_case;
}

test "keycode" {
    const TestType = struct { []const u8, KeyCode };
    const tests = [_]TestType{
        .{ "a", .printable },
        .{ ":", .printable },
        .{ "q", .printable },
        .{ "\x0d", .enter },
    };
    for (tests) |t| {
        var buf: [8]u8 = undefined;
        for (t[0], 0..) |c, i| buf[i] = c;
        const actual = try parseInput(buf, t[0].len);
        try testing.expectEqual(t[1], actual.key_code);
    }
}

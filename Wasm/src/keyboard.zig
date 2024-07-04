const std = @import("std");

pub const KeyType = enum {
    w,
    a,
    s,
    d,
};

const key_map = std.StaticStringMap(KeyType).initComptime(.{
    .{ "w", KeyType.w },
    .{ "a", KeyType.a },
    .{ "s", KeyType.s },
    .{ "d", KeyType.d },
});

pub var key_pressed = std.EnumSet(KeyType).initEmpty();

pub fn is_pressed(key: KeyType) bool {
    return key_pressed.contains(key);
}

pub fn set_pressed(key_str: []const u8, pressed: bool) void {
    const key = key_map.get(key_str);
    if (key) |k| {
        key_pressed.setPresent(k, pressed);
    }
}

const std = @import("std");
const testing = std.testing;
const GapBuffer = @import("gap_buffer.zig").GapBuffer;
const Allocator = std.mem.Allocator;
const unicode = std.unicode;
const assert = std.debug.assert;

pub const CoreEditor = struct {
    const Self = @This();
    const tab_indentation = 4;
    const spaces = " " ** tab_indentation;
    /// New line arraylists are initialized with this capacity
    const line_initial_capacity = 10;

    /// The current line the cursor is on
    y: usize = 0,
    /// The current character a cursor is on
    x: usize = 0,
    /// The current byte the cursor is on
    byte_x: usize = 0,
    last_x: usize = 0,
    line_max_x: usize = 0,
    content: GapBuffer(GapBuffer(u8)),
    allocator: Allocator,

    pub fn init(allocator: std.mem.Allocator) Allocator.Error!Self {
        var buffer = try GapBuffer(GapBuffer(u8)).initCapacity(allocator, 1000);
        const line = try GapBuffer(u8).initCapacity(allocator, line_initial_capacity);
        try buffer.insert(line);
        return Self{
            .content = buffer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Self) void {
        var iterator = self.content.iterator();
        while (iterator.next()) |line| {
            line.deinit();
        }
        self.content.deinit();
    }

    /// Computes the amount of bytes the first `charX` characters take up.
    /// Runs in O(n)
    fn computeBytePosition(self: Self, gap: GapBuffer(u8), char_x: usize) !usize {
        var byte_x: usize = 0;
        if (gap.len > 0) {
            const owned = try gap.getOwnedSlice();
            defer self.allocator.free(owned);
            var iter = (try unicode.Utf8View.init(owned)).iterator();
            var i: usize = 0;
            while (iter.nextCodepointSlice()) |ch| : (i += 1) {
                if (i >= char_x) break;
                byte_x += ch.len;
            }
        }
        return byte_x;
    }

    /// Jump to a specific character position.
    /// Resets `last_x`.
    pub fn jump(self: *Self, y: usize, x: usize) !void {
        assert(y <= self.content.len);
        self.content.jump(y + 1);
        var line = self.content.getLeft();
        assert(x <= line.len);
        self.y = y;
        self.x = x;
        self.last_x = x;
        self.byte_x = try self.computeBytePosition(line.*, self.x);
        line.jump(self.byte_x);
    }

    /// Inserts a slice of characters at the current cursor position.
    /// Does not handle different character types. `addChars` should
    /// be used for that.
    fn insertSlice(self: *Self, chars: []const u8) !void {
        try self.content.get(self.y).insertSlice(chars);
        const chars_added = try unicode.utf8CountCodepoints(chars);
        self.x += chars_added;
        self.last_x = self.x;
        self.byte_x += chars.len;
        self.line_max_x += chars_added;
    }

    //// Inserts a newline at the current cursor position
    fn insertNewline(self: *Self) !void {
        const old_line_length = self.content.getLeft().len;
        try self.content.insert(try GapBuffer(u8).initCapacity(self.allocator, line_initial_capacity));
        if (self.byte_x < old_line_length) {
            const new_line = self.content.getLeft();
            const old_line = self.content.get(self.y);
            try new_line.insertSlice(old_line.buffer.items[self.byte_x..old_line_length]);
            self.line_max_x = try unicode.utf8CountCodepoints(old_line.buffer.items[self.byte_x..old_line_length]);
            old_line.deleteAllRight();
        } else {
            self.line_max_x = 0;
        }
        self.y += 1;
        self.x = 0;
        self.last_x = 0;
        self.byte_x = 0;
    }

    /// Takes an unfiltered input of characters and inserts them at
    /// the current cursor position. Handles special characters like
    /// newlines and tabs.
    pub fn addChars(self: *Self, chars: []const u8) !void {
        var start: usize = 0;
        var pos: usize = 0;
        for (chars, 0..) |c, i| {
            switch (c) {
                '\n' => {
                    if (start < i) {
                        try self.insertSlice(chars[start..i]);
                    }
                    try self.insertNewline();
                    start = i + 1;
                    pos = 0;
                },
                '\t' => {
                    if (start < i) {
                        try self.insertSlice(chars[start..i]);
                    }
                    const spaces_to_add = 4 - pos % 4;
                    try self.insertSlice(spaces[0..spaces_to_add]);
                    pos += spaces_to_add + i - start;
                    start = i + 1;
                },
                else => {},
            }
        }
        if (start < chars.len) {
            try self.insertSlice(chars[start..]);
        }
    }

    fn getMaxCharPos(self: *Self) !struct { byte_x: usize, char_x: usize } {
        const owned = try self.content.getLeft().*.getOwnedSlice();
        defer self.allocator.free(owned);
        var iter = (try unicode.Utf8View.init(owned)).iterator();
        var i: usize = 0;
        var byte_x: usize = 0;
        while (iter.nextCodepointSlice()) |ch| : (i += 1) {
            byte_x += ch.len;
        }
        return .{ .byte_x = byte_x, .char_x = i };
    }

    /// Moves the cursor up. Caps up to line 0.
    pub fn moveUp(self: *Self, times: usize) !void {
        const pre_last_x = self.last_x;
        const pre_x = @max(self.x, self.last_x);
        try self.jump(self.y -| times, 0);
        self.line_max_x = (try self.getMaxCharPos()).char_x;
        self.x = @min(pre_x, self.line_max_x);
        self.last_x = pre_last_x;
        self.byte_x = try self.computeBytePosition(self.content.getLeft().*, self.x);
    }

    /// Moves the cursor down. Caps down to the last line.
    pub fn moveDown(self: *Self, times: usize) !void {
        const pre_last_x = self.last_x;
        const pre_x = @max(self.x, self.last_x);
        try self.jump(@min(self.y + times, self.content.len), 0);
        self.line_max_x = (try self.getMaxCharPos()).char_x;
        self.x = @min(pre_x, self.line_max_x);
        self.last_x = pre_last_x;
        self.byte_x = try self.computeBytePosition(self.content.getLeft().*, self.x);
    }

    /// Moves the cursor to the left. Caps to index 0.
    pub fn moveLeft(self: *Self, times: usize) !void {
        try self.jump(self.y, self.x -| times);
    }

    /// Moves the cursor to the right. Caps to the last character.
    pub fn moveRight(self: *Self, times: usize) !void {
        try self.jump(self.y, @min(self.x + times, self.line_max_x));
    }
};

test "init" {
    var term = try CoreEditor.init(testing.allocator);
    defer term.deinit();
    try testing.expectEqual(@as(usize, 0), term.x);
    try testing.expectEqual(@as(usize, 0), term.y);
    try testing.expectEqual(@as(usize, 1), term.content.len);
    try testing.expectEqual(@as(usize, 0), term.content.buffer.items[0].len);
}

test "init with failing allocator" {
    const terminal = CoreEditor.init(testing.failing_allocator);
    try testing.expectError(std.mem.Allocator.Error.OutOfMemory, terminal);
}

test "computeBytePosition" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        const gap = GapBuffer(u8).init(a);
        try testing.expectEqual(@as(usize, 0), try term.computeBytePosition(gap, 0));
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        var gap = GapBuffer(u8).init(a);
        defer gap.deinit();
        try gap.insertSlice("äääää");
        try testing.expectEqual(@as(usize, 10), try term.computeBytePosition(gap, 5));
    }
}

test "jump" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.jump(0, 0);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 0), term.x);
        try testing.expectEqual(@as(usize, 0), term.last_x);
        try testing.expectEqual(@as(usize, 0), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("hello\nthere\ngeneral\nkenobi");
        try term.jump(3, 4);
        try testing.expectEqual(@as(usize, 3), term.y);
        try testing.expectEqual(@as(usize, 4), term.x);
        try testing.expectEqual(@as(usize, 4), term.last_x);
        const line = term.content.getLeft().*;
        try testing.expectEqual(@as(u8, 'o'), line.getLeft().*);
        try testing.expectEqual(@as(u8, 'b'), line.getRight().*);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("äää\nöööö");
        try term.jump(1, 3);
        try testing.expectEqual(@as(usize, 1), term.y);
        try testing.expectEqual(@as(usize, 3), term.x);
        try testing.expectEqual(@as(usize, 3), term.last_x);
        try testing.expectEqual(@as(usize, 6), term.byte_x);
    }
}

test "insertSlice" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.insertSlice("asdf");
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 4), term.x);
        try testing.expectEqual(@as(usize, 4), term.last_x);
        try testing.expectEqual(@as(usize, 4), term.byte_x);
        try testing.expectEqual(@as(usize, 4), term.line_max_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.insertSlice("äüＳ");
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 3), term.x);
        try testing.expectEqual(@as(usize, 3), term.last_x);
        try testing.expectEqual(@as(usize, 3), term.line_max_x);
        try testing.expectEqual(@as(usize, 7), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.insertSlice("2345");
        try term.jump(0, 0);
        try term.insertSlice("01");
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 2), term.x);
        try testing.expectEqual(@as(usize, 2), term.last_x);
        try testing.expectEqual(@as(usize, 6), term.line_max_x);
        try testing.expectEqual(@as(usize, 2), term.byte_x);
        const line = try term.content.get(0).getOwnedSlice();
        defer a.free(line);
        try testing.expectEqualSlices(u8, "012345", line);
    }
}

test "insertNewline" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.insertSlice("a");
        try term.insertNewline();
        try testing.expectEqual(@as(usize, 1), term.y);
        try testing.expectEqual(@as(usize, 0), term.x);
        try testing.expectEqual(@as(usize, 0), term.last_x);
        try testing.expectEqual(@as(usize, 0), term.line_max_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.insertSlice("abcd");
        try term.jump(0, 2);
        try term.insertNewline();
        try testing.expectEqual(@as(usize, 2), term.content.len);
        const firstLine = try term.content.get(0).getOwnedSlice();
        defer a.free(firstLine);
        const secondLine = try term.content.get(1).getOwnedSlice();
        defer a.free(secondLine);
        try testing.expectEqual(@as(usize, 1), term.y);
        try testing.expectEqual(@as(usize, 0), term.x);
        try testing.expectEqual(@as(usize, 0), term.last_x);
        try testing.expectEqual(@as(usize, 2), term.line_max_x);
        try testing.expectEqualSlices(u8, "ab", firstLine);
        try testing.expectEqualSlices(u8, "cd", secondLine);
    }
}

test "addChars" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("hello");
        const owned = try term.content.get(0).getOwnedSlice();
        defer a.free(owned);
        try testing.expectEqual(@as(usize, 1), term.content.len);
        try testing.expectEqual(@as(usize, 5), owned.len);
        try testing.expectEqualSlices(u8, "hello", owned);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 5), term.x);
        try testing.expectEqual(@as(usize, 5), term.last_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("Hello there\nGeneral Kenobi");
        const firstLine = try term.content.get(0).getOwnedSlice();
        const secondLine = try term.content.get(1).getOwnedSlice();
        defer a.free(firstLine);
        defer a.free(secondLine);
        try testing.expectEqual(@as(usize, 2), term.content.len);
        try testing.expectEqual(@as(usize, 11), firstLine.len);
        try testing.expectEqual(@as(usize, 14), secondLine.len);
        try testing.expectEqualSlices(u8, "Hello there", firstLine);
        try testing.expectEqualSlices(u8, "General Kenobi", secondLine);
        try testing.expectEqual(@as(usize, 1), term.y);
        try testing.expectEqual(@as(usize, 14), term.x);
        try testing.expectEqual(@as(usize, 14), term.last_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("\tdef foo()");
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 13), term.x);
        try testing.expectEqual(@as(usize, 13), term.last_x);
        try testing.expectEqual(@as(usize, 13), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("\tdef\t\tfoo()");
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 17), term.x);
        try testing.expectEqual(@as(usize, 17), term.last_x);
        try testing.expectEqual(@as(usize, 17), term.byte_x);
    }
}

test "moveUp" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("1\n2\n3");
        try term.moveUp(2);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 1), term.x);
        try testing.expectEqual(@as(usize, 1), term.last_x);
        try testing.expectEqual(@as(usize, 1), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("ä\n2\n3");
        try term.moveUp(2);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 1), term.x);
        try testing.expectEqual(@as(usize, 1), term.last_x);
        try testing.expectEqual(@as(usize, 2), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("1234\na\n12345");
        try term.moveUp(99);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 4), term.x);
        try testing.expectEqual(@as(usize, 5), term.last_x);
        try testing.expectEqual(@as(usize, 4), term.byte_x);
    }
}

test "moveDown" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("1234\na\n12345");
        try term.jump(0, 4);
        try term.moveDown(2);
        try testing.expectEqual(@as(usize, 2), term.y);
        try testing.expectEqual(@as(usize, 4), term.x);
        try testing.expectEqual(@as(usize, 4), term.last_x);
        try testing.expectEqual(@as(usize, 4), term.byte_x);
    }
}

test "moveLeft" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("a");
        try term.moveLeft(99);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 0), term.x);
        try testing.expectEqual(@as(usize, 0), term.last_x);
        try testing.expectEqual(@as(usize, 0), term.byte_x);
    }
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.addChars("äbcdéf");
        try term.moveLeft(1);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 5), term.x);
        try testing.expectEqual(@as(usize, 5), term.last_x);
        try testing.expectEqual(@as(usize, 7), term.byte_x);
    }
}

test "moveRight" {
    const a = testing.allocator;
    {
        var term = try CoreEditor.init(a);
        defer term.deinit();
        try term.moveRight(99);
        try testing.expectEqual(@as(usize, 0), term.y);
        try testing.expectEqual(@as(usize, 0), term.x);
        try testing.expectEqual(@as(usize, 0), term.last_x);
        try testing.expectEqual(@as(usize, 0), term.byte_x);
    }
}

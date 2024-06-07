const std = @import("std");
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const testing = std.testing;

pub fn GapBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const K = 10;

        buffer: ArrayList(T),
        gap: usize = 0,
        front: usize = 0,
        len: usize = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .buffer = ArrayList(T).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn initCapacity(allocator: std.mem.Allocator, num: usize) std.mem.Allocator.Error!Self {
            return Self{
                .buffer = try ArrayList(T).initCapacity(allocator, num),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.buffer.deinit();
        }

        /// Inserts `k` gaps and shifts the right elements over by `k`.
        /// O(n)
        pub fn grow(self: *Self, k: usize) !void {
            try self.buffer.resize(self.len + self.gap + k);

            if (self.len - self.front > 0) {
                var i = self.len + self.gap - 1;
                // can't use memcpy because src/dest likely overlaps
                while (i >= self.front + self.gap) : (i -= 1) {
                    self.buffer.items[i + k] = self.buffer.items[i];
                }
            }
            self.gap += k;
        }

        /// O(n), amortized O(1)
        /// May invalidate pointers.
        pub fn insert(self: *Self, value: T) !void {
            if (self.gap == 0) {
                try self.grow(growMinSize(self.len, 1));
            }
            self.buffer.items[self.front] = value;
            self.gap -= 1;
            self.front += 1;
            self.len += 1;
        }

        /// Inserts items into the gap. More efficient than
        /// individual `insert` calls.
        pub fn insertSlice(self: *Self, items: []const T) !void {
            assert(items.len > 0);
            if (self.gap < items.len) {
                try self.grow(growMinSize(self.len, items.len));
            }
            @memcpy(self.buffer.items[self.front .. self.front + items.len], items);
            self.gap -= items.len;
            self.front += items.len;
            self.len += items.len;
        }

        /// Deletes one element to the left of the gap
        pub fn delete(self: *Self) void {
            assert(self.front > 0);
            self.gap += 1;
            self.front -= 1;
            self.len -= 1;
        }

        /// Deletes multiple elements to the left of the gap
        pub fn deleteMany(self: *Self, num: usize) void {
            assert(self.front >= num);
            self.gap += num;
            self.front -= num;
            self.len -= num;
        }

        /// Deletes all elements to the left of the buffer
        pub fn deleteAllLeft(self: *Self) void {
            self.gap += self.front;
            self.len -= self.front;
            self.front = 0;
        }

        /// Deletes one element to the right of the gap
        pub fn deleteRight(self: *Self) void {
            assert(self.len - self.front > 0);
            self.gap += 1;
            self.len -= 1;
        }

        /// Deletes multiple elements to the right of the gap
        pub fn deleteManyRight(self: *Self, num: usize) void {
            assert(self.len - self.front >= num);
            self.gap += num;
            self.len -= num;
        }

        /// Deletes all elements to the right of the buffer
        pub fn deleteAllRight(self: *Self) void {
            const end = self.len - self.front;
            self.gap += end;
            self.len -= end;
        }

        pub fn deleteAll(self: *Self) void {
            self.gap += self.len;
            self.len = 0;
            self.front = 0;
        }

        /// Moves the gap to the left by one.
        /// Asserts the gap is non-empty.
        pub fn left(self: *Self) void {
            assert(self.front > 0);
            if (self.gap > 0) {
                self.buffer.items[self.front + self.gap - 1] = self.buffer.items[self.front - 1];
            }
            self.front -= 1;
        }

        /// Moves the gap to the right by one.
        /// Asserts the gap is non-empty
        pub fn right(self: *Self) void {
            assert(self.len - self.front > 0);
            if (self.gap > 0) {
                self.buffer.items[self.front] = self.buffer.items[self.front + self.gap];
            }
            self.front += 1;
        }

        /// Moves the gap to a specific index in O(n).
        /// Legal index is an element of the inclusive
        /// range [0, n].
        pub fn jump(self: *Self, index: usize) void {
            assert(index <= self.len);
            if (index == self.front) {
                return;
            } else if (index < self.front) {
                for (self.front - index) |_| self.left();
            } else {
                for (index - self.front) |_| self.right();
            }
        }

        /// Asserts the index is a valid element
        /// Returns a pointer to the element.
        pub fn get(self: Self, index: usize) *T {
            assert(index < self.len);
            if (index >= self.front) {
                return &self.buffer.items[index + self.gap];
            }
            return &self.buffer.items[index];
        }

        /// Gets the first element to the left of the gap
        pub fn getLeft(self: Self) *T {
            assert(self.front > 0);
            return &self.buffer.items[self.front - 1];
        }

        /// Gets the first element to the right of the gap
        pub fn getRight(self: Self) *T {
            assert(self.len - self.front > 0);
            return &self.buffer.items[self.front + self.gap];
        }

        /// Copies the buffer into a new slice without any gaps.
        /// The caller owns the returned memory. Should not be freed
        /// on an empty slice.
        pub fn getOwnedSlice(self: Self) ![]T {
            var slice = try self.allocator.alloc(T, self.len);
            @memcpy(slice[0..self.front], self.buffer.items[0..self.front]);
            @memcpy(slice[self.front..], self.buffer.items[self.front + self.gap .. self.len + self.gap]);
            return slice;
        }

        pub const Iterator = struct {
            index: usize = 0,
            gapBuffer: GapBuffer(T),

            pub fn next(it: *Iterator) ?*T {
                if (it.index >= it.gapBuffer.len) return null;
                const out = it.gapBuffer.get(it.index);
                it.index += 1;
                return out;
            }
            pub fn reset(it: *Iterator) void {
                it.index = 0;
            }
        };

        pub fn iterator(self: Self) Iterator {
            return Iterator{ .gapBuffer = self };
        }
    };
}

/// Called when memory growth is necessary. Returns a capacity larger than
/// minimum that grows super-linearly.
/// Taken from std.ArrayList.
fn growMinSize(current: usize, minimum: usize) usize {
    var new = current;
    while (true) {
        new +|= new / 2 + 8;
        if (new >= minimum)
            return new;
    }
}

test "init" {
    const gap = GapBuffer(i256).init(testing.allocator);
    defer gap.deinit();
    try testing.expectEqual(@as(usize, 0), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expectEqual(@as(usize, 0), gap.gap);
}

test "initCapacity" {
    const gap = try GapBuffer(i256).initCapacity(testing.allocator, 500);
    defer gap.deinit();
    try testing.expectEqual(@as(usize, 0), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expectEqual(@as(usize, 0), gap.gap);
}

test "initCapacity with failing allocator" {
    const gap = GapBuffer(i256).initCapacity(testing.failing_allocator, 500);
    try testing.expectError(std.mem.Allocator.Error.OutOfMemory, gap);
}

test "growMinSize" {
    try std.testing.expect(growMinSize(1, 2) >= 1);
    try std.testing.expect(growMinSize(0, 578) >= 578);
    try std.testing.expect(growMinSize(2, 1e6) >= 1e6);
}

test "grow" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.grow(50);
    try gap.insertSlice("12345");
    gap.jump(2);
    try gap.grow(5);
    try std.testing.expectEqual(@as(usize, 5), gap.len);
    try std.testing.expectEqual(@as(usize, 50), gap.gap);
    try std.testing.expectEqual(@as(usize, 2), gap.front);
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, "12345", actual);
}

test "insert" {
    {
        var gap = GapBuffer(i128).init(testing.allocator);
        defer gap.deinit();
        try gap.insert(1);
        try gap.insert(2);
        try gap.insert(3);
        try gap.insert(4);
        const actual = try gap.getOwnedSlice();
        defer testing.allocator.free(actual);
        try testing.expectEqualSlices(i128, &[_]i128{ 1, 2, 3, 4 }, actual);
        try testing.expectEqual(@as(usize, 4), gap.len);
        try testing.expectEqual(@as(usize, 4), gap.front);
    }
    {
        var gap = GapBuffer(GapBuffer(u8)).init(testing.allocator);
        defer gap.deinit();
        try gap.insert(GapBuffer(u8).init(testing.allocator));
        const i = gap.get(0);
        defer i.deinit();
        try gap.get(0).insert(1);
        try testing.expectEqual(@as(usize, 1), gap.len);
        try testing.expectEqual(@as(usize, 1), i.len);
    }
}

test "insert with failing allocator" {
    var gap = GapBuffer(u8).init(testing.failing_allocator);
    defer gap.deinit();
    const res = gap.insert(1);
    try testing.expectError(std.mem.Allocator.Error.OutOfMemory, res);
}

test "slice insert" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("test");
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, "test", actual);
}

test "slice insert move" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("hello");
    gap.left();
    gap.left();
    try gap.insertSlice(" world ");
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, "hel world lo", actual);
}

test "delete" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(5);
    gap.delete();
    try testing.expectEqual(@as(usize, 0), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteMany" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.deleteMany(3);
    try testing.expectEqual(@as(usize, 2), gap.len);
    try testing.expectEqual(@as(usize, 2), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteAllLeft" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.left();
    gap.deleteAllLeft();
    try testing.expectEqual(@as(usize, 1), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteRight" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.left();
    gap.deleteRight();
    try testing.expectEqual(@as(usize, 4), gap.len);
    try testing.expectEqual(@as(usize, 4), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteManyRight" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.jump(0);
    gap.deleteManyRight(5);
    try testing.expectEqual(@as(usize, 0), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteAllRight" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.jump(2);
    gap.deleteAllRight();
    try testing.expectEqual(@as(usize, 2), gap.len);
    try testing.expectEqual(@as(usize, 2), gap.front);
    try testing.expect(gap.gap > 0);
}

test "deleteAll" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.jump(2);
    gap.deleteAll();
    try testing.expectEqual(@as(usize, 0), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expect(gap.gap > 0);
}

test "left" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    gap.left();
    try testing.expectEqual(@as(usize, 1), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    try testing.expect(gap.gap > 0);
}

test "right" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    gap.left();
    try testing.expectEqual(@as(usize, 1), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    gap.right();
    try testing.expectEqual(@as(usize, 1), gap.len);
    try testing.expectEqual(@as(usize, 1), gap.front);
    try testing.expect(gap.gap > 0);
}

test "jump" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.jump(0);
    try testing.expectEqual(@as(usize, 5), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    gap.jump(5);
    try testing.expectEqual(@as(usize, 5), gap.len);
    try testing.expectEqual(@as(usize, 5), gap.front);
    try testing.expect(gap.gap > 0);
}

test "move and grow" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    const expected = [_]u8{ 1, 2, 3 };
    try gap.insertSlice(&expected);
    gap.left();
    gap.left();
    gap.left();
    gap.right();
    try gap.grow(5);
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, &expected, actual);
}

test "move back and forth" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    try gap.insert(3);
    try gap.insert(4);
    try gap.insert(5);
    gap.left();
    gap.left();
    gap.left();
    gap.left();
    gap.left();
    try testing.expectEqual(@as(usize, 5), gap.len);
    try testing.expectEqual(@as(usize, 0), gap.front);
    gap.right();
    gap.right();
    gap.right();
    gap.right();
    gap.right();
    try testing.expectEqual(@as(usize, 5), gap.len);
    try testing.expectEqual(@as(usize, 5), gap.front);
}

test "jump and insert" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    gap.jump(0);
    try gap.insertSlice("|54321");
    gap.jump(6);
    try gap.insert('|');
    gap.jump(12);
    try gap.insert('|');
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, "|54321|12345|", actual);
}

test "insert movement combination" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(5);
    gap.left();
    gap.right();
    try gap.insert(3);
    gap.left();
    try gap.insert(2);
    gap.left();
    gap.left();
    try gap.insert(1);
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 5, 2, 3 }, actual);
}

test "delete complex" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    gap.left();
    gap.delete();
    try gap.insert(3);
    gap.right();
    try gap.insert(4);
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, &[_]u8{ 3, 2, 4 }, actual);
}

test "get" {
    {
        var gap = GapBuffer(u8).init(testing.allocator);
        defer gap.deinit();
        try gap.insertSlice("12345");
        gap.left();
        try testing.expectEqual(@as(usize, '1'), gap.get(0).*);
        try testing.expectEqual(@as(usize, '5'), gap.get(4).*);
    }
    {
        var gap = GapBuffer(u8).init(testing.allocator);
        defer gap.deinit();
        try gap.insert(1);
        try gap.insert(2);
        gap.left();
        try testing.expectEqual(@as(u8, 1), gap.get(0).*);
        try testing.expectEqual(@as(u8, 2), gap.get(1).*);
    }
}

test "getLeft" {
    var gap = GapBuffer(i32).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(600);
    try testing.expectEqual(@as(i32, 600), gap.getLeft().*);
}

test "getRight" {
    var gap = GapBuffer(i32).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(600);
    gap.left();
    try testing.expectEqual(@as(i32, 600), gap.getRight().*);
}

test "getOwnedSlice" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insertSlice("12345");
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, "12345", actual);
}

test "iterator complex" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    try gap.insert(3);
    try gap.insert(4);
    var iterator = gap.iterator();
    const expect = [_]u8{ 1, 2, 3, 4 };
    var i: u8 = 0;
    while (iterator.next()) |elem| : (i += 1) {
        try std.testing.expectEqual(expect[i], elem.*);
    }
}

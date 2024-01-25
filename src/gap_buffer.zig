const std = @import("std");
const ArrayList = std.ArrayList;
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

        pub fn initCapacity(allocator: std.mem.Allocator, num: usize) Self {
            return Self{
                .buffer = ArrayList(T).initCapacity(allocator, num),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        /// Inserts `k` gaps and shifts the other elements over by `k`.
        /// O(n)
        pub fn grow(self: *Self, k: usize) !void {
            try self.buffer.appendNTimes(0, k);
            @memcpy(
                self.buffer.items[self.front + self.gap .. self.len + self.gap],
                self.buffer.items[self.front .. self.front + self.gap],
            );
            self.gap += k;
        }

        /// O(n), amortized O(1)
        pub fn insert(self: *Self, value: T) !void {
            if (self.gap == 0) {
                try self.grow(K);
            }
            self.buffer.items[self.front] = value;
            self.gap -= 1;
            self.front += 1;
            self.len += 1;
        }

        pub fn delete(self: *Self) void {
            self.gap += 1;
            self.front -= 1;
            self.len -= 1;
        }

        /// Asserts the gap is non-empty
        pub fn left(self: *Self) void {
            self.buffer.items[self.front + self.gap - 1] = self.buffer.items[self.front - 1];
            self.front -= 1;
        }

        /// Asserts the gap is non-empty
        pub fn right(self: *Self) void {
            self.buffer.items[self.front] = self.buffer.items[self.front + self.gap];
            self.front += 1;
        }

        /// Asserts the index is a valid element
        pub fn get(self: Self, index: usize) T {
            if (index >= self.front) {
                return self.buffer.items[index + self.gap];
            }
            return self.buffer.items[index];
        }

        /// Copies the buffer into a new slice without any gaps.
        /// The caller owns the returned memory.
        pub fn getOwnedSlice(self: Self) ![]T {
            var slice = try self.allocator.alloc(T, self.len);
            @memcpy(slice[0..self.front], self.buffer.items[0..self.front]);
            @memcpy(slice[self.front..], self.buffer.items[self.front + self.gap .. self.gap + self.len]);
            return slice;
        }

        pub const Iterator = struct {
            index: usize = 0,
            gapBuffer: GapBuffer(T),

            pub fn next(it: *Iterator) ?T {
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

test "simple inserts" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    try gap.insert(3);
    try gap.insert(4);
    const actual = try gap.getOwnedSlice();
    defer testing.allocator.free(actual);
    try testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4 }, actual);
    try testing.expectEqual(@as(usize, 4), gap.len);
    try testing.expectEqual(@as(usize, 4), gap.front);
}

test "movement" {
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

test "delete" {
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
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    gap.left();
    try testing.expectEqual(@as(u8, 1), gap.get(0));
    try testing.expectEqual(@as(u8, 2), gap.get(1));
}

test "iterator" {
    var gap = GapBuffer(u8).init(testing.allocator);
    defer gap.deinit();
    try gap.insert(1);
    try gap.insert(2);
    try gap.insert(3);
    try gap.insert(4);
    var iterator = gap.iterator();
    const expect = [_]u8{ 1, 2, 3, 4 };
    var i: u8 = 0;
    while (iterator.next()) |elem| {
        try std.testing.expectEqual(expect[i], elem);
        i += 1;
    }
}

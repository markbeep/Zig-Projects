const std = @import("std");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

var buffer = std.mem.zeroes([16]u8);

export fn getBufferPointer() [*]u8 {
    return @ptrCast(&buffer);
}

export fn computeBuffer() void {
    for (0..buffer.len) |i| {
        buffer[i] = @intCast(i);
    }
}

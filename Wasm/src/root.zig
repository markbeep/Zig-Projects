const std = @import("std");
const p = @import("perlin.zig");

extern fn print(i32) void;

// 500x500*3 RGB pixels
const width = 500;
const height = 500;
var buffer: [width * height * 3]u8 = undefined;

export fn getBufferPointer() [*]u8 {
    return @ptrCast(&buffer);
}

export fn setSeed(s: i32) void {
    p.setSeed(s);
}

export fn computePerlin() void {
    for (0..height) |y| {
        for (0..width) |x| {
            const fy: f32 = @floatFromInt(y);
            const fx: f32 = @floatFromInt(x);
            const value = p.perlin(fx, fy);
            const gray: u8 = @intFromFloat((value / 1.0 * 256.0));
            buffer[(y * width + x) * 3] = gray;
            buffer[(y * width + x) * 3 + 1] = gray;
            buffer[(y * width + x) * 3 + 2] = gray;
        }
    }
}

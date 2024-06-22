const std = @import("std");
const sqrt = std.math.sqrt;
const pow = std.math.pow;
const p = @import("perlin.zig");

extern fn drawBuffer(buffer_address: [*]u8) void;

// 500x500*4 RGBA pixels
const width = 500;
const height = 500;
var buffer: [width * height * 4]u8 = undefined;
var w_pressed = false;
var a_pressed = false;
var s_pressed = false;
var d_pressed = false;
var x_pos: f64 = 1.0;
var y_pos: f64 = 1.0;
var last_time: f64 = 0.0;

export fn init() void {}

export fn update(timestamp: f64) void {
    const delta_time = if (last_time == 0.0) 0.0 else timestamp - last_time;
    last_time = timestamp;

    if (w_pressed) {
        y_pos -= 0.1 * delta_time;
    }
    if (a_pressed) {
        x_pos -= 0.1 * delta_time;
    }
    if (s_pressed) {
        y_pos += 0.1 * delta_time;
    }
    if (d_pressed) {
        x_pos += 0.1 * delta_time;
    }

    for (0..height) |y| {
        for (0..width) |x| {
            if (y == 0 or y == height - 1 or x == 0 or x == width - 1) {
                setColor(x, y, 255, 255, 255, 255);
                continue;
            }

            const y_diff = pow(f64, y_pos - @as(f64, @floatFromInt(y)), 2);
            const x_diff = pow(f64, x_pos - @as(f64, @floatFromInt(x)), 2);
            const dist = sqrt(y_diff + x_diff);

            if (dist < 5.0) {
                setColor(x, y, 255, 0, 0, 255);
            } else {
                setColor(x, y, 0, 0, 0, 255);
            }
        }
    }

    drawBuffer(&buffer);
}

export fn keyboard(key: u16, pressed: bool) void {
    switch (key) {
        'w', 'W' => w_pressed = pressed,
        'a' | 'A' => a_pressed = pressed,
        's' | 'S' => s_pressed = pressed,
        'd' | 'D' => d_pressed = pressed,
        else => {},
    }
}

fn setColor(x: usize, y: usize, r: u8, g: u8, b: u8, a: u8) void {
    buffer[(y * width + x) * 4] = r;
    buffer[(y * width + x) * 4 + 1] = g;
    buffer[(y * width + x) * 4 + 2] = b;
    buffer[(y * width + x) * 4 + 3] = a;
}

fn computePerlin() void {
    for (0..height) |y| {
        for (0..width) |x| {
            const fy: f32 = @floatFromInt(y);
            const fx: f32 = @floatFromInt(x);
            const value = p.perlin(fx, fy);
            const gray: u8 = @intFromFloat((value / 1.0 * 256.0));
            buffer[(y * width + x) * 4] = gray;
            buffer[(y * width + x) * 4 + 1] = gray;
            buffer[(y * width + x) * 4 + 2] = gray;
            buffer[(y * width + x) * 4 + 3] = 255;
        }
    }
}

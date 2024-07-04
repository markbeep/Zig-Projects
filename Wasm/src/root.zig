const std = @import("std");
const sqrt = std.math.sqrt;
const pow = std.math.pow;
const assert = std.debug.assert;
const k = @import("keyboard.zig");

extern fn drawBuffer(buffer_address: [*]u8) void;

// 500x500*4 RGBA pixels
const width = 500;
const height = 500;
var buffer: [width * height * 4]u8 = undefined;
/// Contains the buffer for the frontend to write keys into
var key_buffer: [32]u8 = undefined;
var x_pos: f64 = 1.0;
var y_pos: f64 = 1.0;
var last_time: f64 = 0.0;
var fps_refresh_counter: usize = 0;
var fps_sum: f64 = 0.0;
var last_fps: usize = 0;

export fn register_keypress(len: u16, pressed: bool) void {
    // Force all keys to lowercase
    for (0..len) |i| {
        if (key_buffer[i] >= 'A' and key_buffer[i] <= 'Z') {
            key_buffer[i] = key_buffer[i] + 32;
        }
    }
    k.set_pressed(key_buffer[0..len], pressed);
}

export fn keyboard_offset() [*]u8 {
    return &key_buffer;
}

/// Called once at the start when the canvas is loaded
export fn init() void {}

/// Called every frame
export fn update(timestamp: f64) void {
    const delta_time = if (last_time == 0.0) 0.0 else timestamp - last_time;
    last_time = timestamp;

    if (k.is_pressed(.w)) {
        y_pos -= 0.1 * delta_time;
    }
    if (k.is_pressed(.a)) {
        x_pos -= 0.1 * delta_time;
    }
    if (k.is_pressed(.s)) {
        y_pos += 0.1 * delta_time;
    }
    if (k.is_pressed(.d)) {
        x_pos += 0.1 * delta_time;
    }

    for (0..height) |y| {
        for (0..width) |x| {
            if (y == 0 or y == height - 1 or x == 0 or x == width - 1) {
                setColor(x, y, 0, 255, 0, 255);
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

    // Draw rough fps
    fps_sum += 1000.0 / delta_time;
    if (fps_refresh_counter == 0) {
        fps_refresh_counter = 50;
        last_fps = @intFromFloat(fps_sum / @as(f64, @floatFromInt(fps_refresh_counter)));
        fps_sum = 0.0;
    } else {
        fps_refresh_counter -= 1;
    }
    fpsCounter(last_fps);

    drawBuffer(&buffer);
}

fn setColor(x: usize, y: usize, r: u8, g: u8, b: u8, a: u8) void {
    buffer[(y * width + x) * 4] = r;
    buffer[(y * width + x) * 4 + 1] = g;
    buffer[(y * width + x) * 4 + 2] = b;
    buffer[(y * width + x) * 4 + 3] = a;
}

const numbers = [_][3][3]bool{
    // 0
    .{
        .{ true, true, true },
        .{ true, false, true },
        .{ true, true, true },
    },
    // 1
    .{
        .{ true, true, false },
        .{ false, true, false },
        .{ true, true, true },
    },
    // 2
    .{
        .{ true, true, false },
        .{ false, true, false },
        .{ false, true, true },
    },
    // 3
    .{
        .{ true, true, true },
        .{ false, true, true },
        .{ true, true, true },
    },
    // 4
    .{
        .{ true, false, true },
        .{ true, true, true },
        .{ false, false, true },
    },
    // 5
    .{
        .{ false, true, true },
        .{ false, true, false },
        .{ true, true, false },
    },
    // 6
    .{
        .{ true, false, false },
        .{ true, true, true },
        .{ true, true, true },
    },
    // 7
    .{
        .{ true, true, true },
        .{ false, false, true },
        .{ false, false, true },
    },
    // 8
    .{
        .{ false, true, true },
        .{ true, true, true },
        .{ true, true, true },
    },
    // 9
    .{
        .{ true, true, true },
        .{ true, true, true },
        .{ false, false, true },
    },
};

fn fpsCounter(num: usize) void {
    var remaining = num;
    var index: usize = 0;
    while (remaining > 0) {
        const digit = remaining % 10;
        remaining /= 10;
        drawDigit(digit, 50 + 20 * index, 50, 5);
        index += 1;
    }
}

fn drawDigit(digit: usize, x: usize, y: usize, scale: usize) void {
    for (0..3) |dy| {
        for (0..3) |dx| {
            if (numbers[digit][dy][dx]) {
                const x0 = dx * scale;
                const y0 = dy * scale;
                for (y0..y0 + scale) |sy| {
                    for (x0..x0 + scale) |sx| {
                        setColor(x + sx, y + sy, 255, 255, 255, 255);
                    }
                }
            }
        }
    }
}

const std = @import("std");

var seed: usize = undefined;

pub fn setSeed(s: i32) void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, s, .big);
    seed = @intCast(std.hash.CityHash32.hash(&buf));
}

const Vector2 = struct {
    x: f32,
    y: f32,
};

fn interpolate(a0: f32, a1: f32, w: f32) f32 {
    if (w < 0.0) {
        return a0;
    } else if (w > 1.0) {
        return a1;
    }
    return (a1 - a0) * w + a0;
}

fn randomGradient(ix: usize, iy: usize) Vector2 {
    const w = 8 * @sizeOf(usize);
    const s = w / 2;
    var a = ix;
    var b = iy;
    a *= seed;
    b ^= a << s | a >> w - s;
    b *= 1911520717;
    a ^= b << s | b >> w - s;
    a *= 2048419325;
    const random: f32 = @as(f32, @floatFromInt(a)) * (3.14159265 / @as(f32, @floatFromInt(~(~@as(usize, 0) >> 1))));
    return Vector2{
        .x = std.math.cos(random * @as(f32, @floatFromInt(ix))),
        .y = std.math.sin(random * @as(f32, @floatFromInt(iy))),
    };
}

fn dotGridGradient(ix: usize, iy: usize, x: f32, y: f32) f32 {
    const gradient = randomGradient(ix, iy);
    const dx = x - @as(f32, @floatFromInt(ix));
    const dy = y - @as(f32, @floatFromInt(iy));
    return dx * gradient.x + dy * gradient.y;
}

pub fn perlin(x: f32, y: f32) f32 {
    // https://en.wikipedia.org/wiki/Perlin_noise
    const x0 = @as(usize, @intFromFloat(x));
    const y0 = @as(usize, @intFromFloat(y));
    const x1 = x0 + 1;
    const y1 = y0 + 1;

    const sx = 1;
    const sy = 1;

    var n0: f32 = undefined;
    var n1: f32 = undefined;
    n0 = dotGridGradient(x0, y0, x, y);
    n1 = dotGridGradient(x1, y0, x, y);
    const fx0 = interpolate(n0, n1, sx);

    n0 = dotGridGradient(x0, y1, x, y);
    n1 = dotGridGradient(x1, y1, x, y);
    const fx1 = interpolate(n0, n1, sx);

    return interpolate(fx0, fx1, sy) * 0.5 + 0.5;
}

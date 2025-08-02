const std = @import("std");
const rl = @import("raylib");

/// `mu` - *mean* of the distribution
/// `sigma` - *standard deviation* of the distribution
/// [Uses Box Muller Transform](https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform)
/// Returns *two* values
pub fn sampleNormalPair(rng: *std.Random.DefaultPrng, mu: f32, sigma: f32) struct { f32, f32 } {
    const two_pi: f32 = std.math.pi * 2.0;
    const val1 = blk: {
        var n = rng.random().float(f32);
        while (n <= 0.0) {
            n = rng.random().float(f32);
        }
        break :blk n;
    };
    const val2 = rng.random().float(f32);
    const mag = sigma * @sqrt(-2.0 * @log(val1));
    const z0 = mag * @cos(two_pi * val2) + mu;
    const z1 = mag * @sin(two_pi * val2) + mu;
    return .{ z0, z1 };
}

fn randomGradient(ix: i32, iy: i32) rl.Vector2 {
    // No precomputed gradients mean this works for any number of grid coordinates
    const w: u64 = 8 * @sizeOf(u64);
    const s: u64 = w / 2;
    var a: u64 = @intCast(ix);
    var b: u64 = @intCast(iy);
    a = a *% 3284157443;

    b ^= a << s | a >> w - s;
    b = b *% 1911520717;

    a ^= b << s | b >> w - s;
    a = a *% 2048419325;
    const random: f32 = @as(f32, @floatFromInt(a)) * (3.14159265 / @as(f32, @floatFromInt(~(~@as(u32, 0) >> 1)))); // in [0, 2*Pi]

    return rl.Vector2.init(@sin(random), @cos(random));
}

// Computes the dot product of the distance and gradient vectors.
fn dotGridGradient(ix: i32, iy: i32, x: f32, y: f32) f32 {
    // Get gradient from integer coordinates
    const gradient = randomGradient(ix, iy);

    // Compute the distance vector
    const dx = x - @as(f32, @floatFromInt(ix));
    const dy = y - @as(f32, @floatFromInt(iy));

    // Compute the dot-product
    return dx * gradient.x + dy * gradient.y;
}

fn interpolate(a0: f32, a1: f32, w: f32) f32 {
    return (a1 - a0) * (3.0 - w * 2.0) * w * w + a0;
}

pub fn perlinSample(x: f32, y: f32) f32 {
    // Determine grid cell corner coordinates
    const x0: i32 = @intFromFloat(x);
    const y0: i32 = @intFromFloat(y);
    const x1: i32 = x0 + 1;
    const y1: i32 = y0 + 1;

    // Compute Interpolation weights
    const sx: f32 = x - @as(f32, @floatFromInt(x0));
    const sy: f32 = y - @as(f32, @floatFromInt(y0));

    // Compute and interpolate top two corners
    var n0: f32 = dotGridGradient(x0, y0, x, y);
    var n1: f32 = dotGridGradient(x1, y0, x, y);
    const ix0: f32 = interpolate(n0, n1, sx);

    // Compute and interpolate bottom two corners
    n0 = dotGridGradient(x0, y1, x, y);
    n1 = dotGridGradient(x1, y1, x, y);
    const ix1 = interpolate(n0, n1, sx);

    // Final step: interpolate between the two previously interpolated values, now in y
    const value = interpolate(ix0, ix1, sy);

    return value;
}

pub fn genPerlinNoise(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng, img: *rl.Image) void {
    _ = allocator;
    _ = rng;
    std.debug.assert(img.width == img.height);
    const size: usize = @intCast(img.width);
    const scale: f32 = 0.05;

    // First, generate a random gradient vector in the range [-1 , 1)
    for (0..size) |y| {
        for (0..size) |x| {
            const xf = @as(f32, @floatFromInt(x)) * scale;
            const yf = @as(f32, @floatFromInt(y)) * scale;
            const v = perlinSample(xf, yf); // [-1,1]
            const normalized = v * 0.5 + 0.5; // map to [0,1]
            const c: u8 = @intFromFloat(255.0 * normalized);
            img.drawPixel(@intCast(x), @intCast(y), rl.Color.init(c, c, c, 255));
        }
    }
}

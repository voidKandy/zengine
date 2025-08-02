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

pub fn genPerlinNoise(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng, img: *rl.Image) void {
    _ = allocator;
    // First, generate a random gradient vector in the range [-1 , 1)
    for (0..@as(usize, @intCast(img.height))) |y| {
        for (0..@as(usize, @intCast(img.width))) |x| {
            // const x_grad = rng.random().float(f32) * 2.0 - 1.0;
            // const y_grad = rng.random().float(f32) * 2.0 - 1.0;
            const n = rng.random().float(f32);
            const c: u8 = @intFromFloat(255.0 * n);
            const color = rl.Color.init(c, c, c, 255);
            img.drawPixel(@intCast(x), @intCast(y), color);
        }
    }
}

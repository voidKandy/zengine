const std = @import("std");
/// `mu` - *mean* of the distribution
/// `sigma` - *standard deviation* of the distribution
/// https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform
pub fn generateGaussianNoise(rng: *std.Random.DefaultPrng, mu: f32, sigma: f32) struct { f32, f32 } {
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

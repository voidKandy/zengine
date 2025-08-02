const std = @import("std");
const rl = @import("raylib");
const zbt = @import("zbullet");
const engine = @import("root.zig");

const Self = @This();
const SamplerFn = fn (f32, f32, u32) f32;
material_mesh: ?engine.MaterialMesh = null,
sample: SamplerFn = engine.noise.perlinSample,
// image: ?rl.Image,

const DEFAULT_COLOR = rl.Color.black;

// pub fn init(img: rl.Image) Self {
//     return .{ .image = img };
// }

// test "implement" {
//     const size = 256;
//     const img = rl.Image.genColor(size, size, rl.Color.black);
//     const this = Self.init(img);
//     std.debug.print(
//         \\ Terrain Bundle Test Passed
//         \\ {any}
//     , .{this});
// }

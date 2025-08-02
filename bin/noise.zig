const std = @import("std");
const engine = @import("engine_core");
const game = @import("game_core");
const zbt = @import("zbullet");
const rl = @import("raylib");

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

fn createNoiseImage(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng, size: i32) !rl.Image {
    var img = rl.Image.genColor(size, size, rl.Color.black);
    engine.noise.genPerlinNoise(allocator, rng, &img);

    return img;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        arena.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("FAIL");
    }

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Noise Data");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const size: i32 = 512;
    const img = try createNoiseImage(arena.allocator(), &rng, size);
    const tx =
        try img.toTexture();
    const render_tex = try rl.RenderTexture2D.init(size, size);
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        // Draw the circle texture to the render texture
        {
            rl.beginTextureMode(render_tex);
            defer rl.endTextureMode();
            rl.drawTextureRec(
                tx,
                rl.Rectangle{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @as(f32, @floatFromInt(size)),
                    .height = -@as(f32, @floatFromInt(size)), // flip vertically
                },
                rl.Vector2{ .x = 0, .y = 0 },
                rl.Color.white,
            );
        }

        // Draw the render texture to the window
        rl.drawTextureRec(
            render_tex.texture,
            rl.Rectangle{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(size)),
                .height = -@as(f32, @floatFromInt(size)), // flip vertically
            },
            rl.Vector2{ .x = 0, .y = 0 },
            rl.Color.white,
        );
    }
}

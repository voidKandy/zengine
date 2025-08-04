const std = @import("std");
const engine = @import("engine_core");
const game = @import("game_core");
const ui = @import("raygui");
const zbt = @import("zbullet");
const rl = @import("raylib");

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

fn createNoiseImage(seed: u32, size: i32, scale: f32) !rl.Image {
    var img = rl.Image.genColor(size, size, rl.Color.black);
    engine.noise.genPerlinNoise(&img, seed, scale);

    return img;
}

/// Create some kind of `StateObject` that has a ui presence
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
    var seed = rng.random().int(u32);
    var scale: f32 = 0.005;
    var last_scale = scale;
    var img = try createNoiseImage(seed, size, scale);
    const render_tex = try rl.RenderTexture2D.init(size, size);

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.r) or last_scale != scale) {
            seed = rng.random().int(u32);
            img = try createNoiseImage(seed, size, scale);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        {
            rl.beginTextureMode(render_tex);
            defer rl.endTextureMode();
            rl.drawTextureRec(
                try img.toTexture(),
                rl.Rectangle{
                    .x = 0.0,
                    .y = 0.0,
                    .width = @as(f32, @floatFromInt(size)),
                    .height = -@as(f32, @floatFromInt(size)),
                },
                rl.Vector2{ .x = 0, .y = 0 },
                rl.Color.white,
            );
        }

        rl.drawTextureRec(
            render_tex.texture,
            rl.Rectangle{
                .x = 0.0,
                .y = 0.0,
                .width = @as(f32, @floatFromInt(size)),
                .height = -@as(f32, @floatFromInt(size)),
            },
            rl.Vector2{ .x = 0, .y = 0 },
            rl.Color.white,
        );
        last_scale = scale;
        _ = ui.guiSliderBar(
            rl.Rectangle{ .x = 10, .y = 10, .width = 200, .height = 20 },
            "Min",
            "Max",
            &scale,
            0.0,
            0.1,
        );
    }
}

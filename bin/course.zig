const std = @import("std");
const rl = @import("raylib");
const math = std.math;
const Vector2 = rl.Vector2;

const screen_width = 800;
const screen_height = 600;

fn randVector2(rng: *std.Random.DefaultPrng, min: f32, max: f32) Vector2 {
    return .{
        .x = rng.random().float(f32) * (max - min) + min,
        .y = rng.random().float(f32) * (max - min) + min,
    };
}

fn drawBlob(center: Vector2, radius: f32, color: rl.Color) void {
    rl.drawCircleV(rl.Vector2{ .x = center.x, .y = center.y }, radius, color);
}

const Hole = struct {
    tee: Vector2,
    green: Vector2,
    control: Vector2,

    pub fn generate(rng: *std.Random.DefaultPrng) Hole {
        const tee = randVector2(rng, 100, 200);
        const green = randVector2(rng, 500, 700);
        const control = randVector2(rng, 300, 500); // curve control point
        return .{ .tee = tee, .green = green, .control = control };
    }

    pub fn draw(self: Hole) void {
        // Draw fairway (basic quadratic curve)
        const steps = 20;
        for (0..steps) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const p = interpolate(self.tee, self.control, self.green, t);
            drawBlob(p, 20.0, rl.Color.green);
        }

        // Draw tee and green
        drawBlob(self.tee, 12.0, rl.Color.blue);
        drawBlob(self.green, 15.0, rl.Color.dark_green);
    }
};

fn interpolate(p0: Vector2, p1: Vector2, p2: Vector2, t: f32) Vector2 {
    // Simple quadratic Bezier: B(t) = (1-t)^2 * P0 + 2*(1-t)*t*P1 + t^2*P2
    const u = 1.0 - t;
    const tt = t * t;
    const uu = u * u;
    return .{
        .x = uu * p0.x + 2.0 * u * t * p1.x + tt * p2.x,
        .y = uu * p0.y + 2.0 * u * t * p1.y + tt * p2.y,
    };
}

pub fn main() !void {
    rl.initWindow(screen_width, screen_height, "Procedural Golf Hole");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var hole = Hole.generate(&rng);

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            hole = Hole.generate(&rng);
        }

        rl.beginDrawing();
        rl.clearBackground(rl.Color.dark_gray);

        hole.draw();

        rl.drawText("Press [R] to regenerate", 10, 10, 20, rl.Color.white);
        rl.endDrawing();
    }
}

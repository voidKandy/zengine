const std = @import("std");
const engine = @import("engine_core");
const zbt = @import("zbullet");
const rl = @import("raylib");
const Vector3 = rl.Vector3;

const screen_width = 800;
const screen_height = 600;

const BOX_MIN: f32 = -5.0;
const BOX_MAX: f32 = 5.0;

fn init_cameras() struct {
    perspective: rl.Camera3D,
    birds_eye: rl.Camera3D,
} {
    return .{ .perspective = rl.Camera{
        .position = rl.Vector3.init(10.0, 10.0, 10.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    }, .birds_eye = rl.Camera3D{
        .position = rl.Vector3.init(0.0, 12.0, 0.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(1.0, 0.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    } };
}

const Camera = enum { perspective, birds_eye };

fn randVector3(rng: *std.Random.DefaultPrng, min: f32, max: f32) Vector3 {
    return .{
        .x = rng.random().float(f32) * (max - min) + min,
        .y = rng.random().float(f32) * (max - min) + min,
        .z = rng.random().float(f32) * (max - min) + min,
    };
}

/// Simple quadratic Bezier: B(t) = (1-t)^2 * P0 + 2*(1-t)*t*P1 + t^2*P2
fn interpolate(p0: Vector3, p1: Vector3, p2: Vector3, t: f32) Vector3 {
    const u = 1.0 - t;
    const tt = t * t;
    const uu = u * u;
    return .{
        .x = uu * p0.x + 2.0 * u * t * p1.x + tt * p2.x,
        .y = uu * p0.y + 2.0 * u * t * p1.y + tt * p2.y,
        .z = uu * p0.z + 2.0 * u * t * p1.z + tt * p2.z,
    };
}

const Plane = struct {
    position: Vector3,
    size: rl.Vector2,
    axis: rl.Vector3,
    /// float between 0 - 90
    angle: f32,

    const deg_2_rad: f32 = std.math.pi / 180.0;

    fn getCornersXZ(plane: Plane) [4]rl.Vector2 {
        const half_w = plane.size.x / 2.0;
        const half_h = plane.size.y / 2.0;
        const rad = plane.angle * std.math.pi / 180.0;

        // Corners in local space
        const local = [4]rl.Vector2{
            .{ .x = -half_w, .y = -half_h },
            .{ .x = half_w, .y = -half_h },
            .{ .x = half_w, .y = half_h },
            .{ .x = -half_w, .y = half_h },
        };

        var world: [4]rl.Vector2 = undefined;
        for (local, &world) |corner, *w| {
            const rotated = rl.Vector2{
                .x = corner.x * @cos(rad) - corner.y * @sin(rad),
                .y = corner.x * @sin(rad) + corner.y * @cos(rad),
            };

            w.* = rl.Vector2{
                .x = rotated.x + plane.position.x,
                .y = rotated.y + plane.position.z,
            };
        }

        return world;
    }

    fn draw(self: @This()) void {
        var corners = [4]rl.Vector3{
            .{ .x = -self.size.x / 2.0, .y = 0.0, .z = -self.size.y / 2.0 },
            .{ .x = self.size.x / 2.0, .y = 0.0, .z = -self.size.y / 2.0 },
            .{ .x = self.size.x / 2.0, .y = 0.0, .z = self.size.y / 2.0 },
            .{ .x = -self.size.x / 2.0, .y = 0.0, .z = self.size.y / 2.0 },
        };

        for (&corners) |*corner| {
            const angle_radians: f32 = self.angle * deg_2_rad;
            // Rotate around the rotation axis
            const rotated = rl.Vector3.rotateByAxisAngle(corner.*, self.axis, angle_radians);
            // Translate to center
            corner.* = rl.Vector3.add(rotated, self.position);
        }

        // Triangle 1: [0, 2, 1]
        rl.drawTriangle3D(corners[0], corners[2], corners[1], rl.Color.green);
        // Triangle 2: [0, 3, 2]
        rl.drawTriangle3D(corners[0], corners[3], corners[2], rl.Color.green);

        // rl.drawRectanglePro(.{ .x = self.position.x, .y = self.position.y, .width = self.size.x, .height = self.size.y }, rl.Vector2.zero(), self.rotation, rl.Color.green);
    }
};

fn generatePolygon(
    comptime N_VERTICES: usize,
    rng: *std.Random.DefaultPrng,
    center: rl.Vector2,
    avg_radius: f32,
    irregularity: f32,
    spikiness: f32,
) [N_VERTICES]rl.Vector2 {
    if (irregularity < 0 or irregularity > 1)
        @panic("Irregularity must be between 0 and 1.");
    if (spikiness < 0 or spikiness > 1)
        @panic("Spikiness must be between 0 and 1.");

    irregularity *= 2 * std.math.pi / N_VERTICES;
    spikiness *= avg_radius;
    const angle_steps = randomAngleSteps(N_VERTICES, irregularity);

    var points: [N_VERTICES]rl.Vector2 = undefined;
    const angle = rng.random().float(f32) * (2 * std.math.pi);

    // last used is 0 if it was just created
    // 1 if the last one used was `@"0"`
    // 2 if the last one used was `0"1"`
    var last_gauss: struct { vals: struct { f32, f32 }, last_used: u2 } = undefined;
    for (&points, &angle_steps) |*p, *step| {
        const sample = blk: {
            while (true) {
                switch (last_gauss.used) {
                    0 => {
                        last_gauss += 1;
                        break :blk last_gauss.vals.@"0";
                    },
                    1 => {
                        last_gauss += 1;
                        break :blk last_gauss.vals.@"0";
                    },
                    else => {
                        last_gauss.vals = engine.noise.generateGaussianNoise(rng, avg_radius, spikiness);
                        last_gauss.used = 0;
                    },
                }
            }
        };

        const radius: f32 = @min(@max(sample, 0.0), 2.0 * avg_radius);

        // radius = clip(random.gauss(avg_radius, spikiness), 0, 2 * avg_radius);
        const point = rl.Vector2.init(center.x + radius * @cos(angle), center.y + radius * @sin(angle));
        p.* = point;
        angle += step.*;
    }
    return points;
}

fn randomAngleSteps(comptime N_STEPS: usize, rng: *std.Random.DefaultPrng, irregularity: f32) [N_STEPS]f32 {
    var angles: [N_STEPS]f32 = undefined;
    const lower = (2.0 * std.math.pi / N_STEPS) - irregularity;
    const upper = (2.0 * std.math.pi / N_STEPS) + irregularity;
    var cumsum: f32 = 0.0;

    for (&angles) |*a| {
        const angle = blk: {
            const f = rng.random().float(f32) * upper;
            while (f < lower) {
                f = rng.random().float(f32) * upper;
            }
            break :blk f;
        };

        a.* = angle;
        cumsum += angle;
    }

    cumsum /= (2 * std.math.pi);
    for (&angles) |*a| {
        a.* /= cumsum;
    }
    return angles;
}
/// Returns an array of exactly A planes, positioned randomly along a Bezier curve
fn randomPlanes(comptime A: usize, rng: *std.Random.DefaultPrng, curve: Curve3D) [A]Plane {
    var result: [A]Plane = undefined;

    for (0..A) |i| {
        const t = rng.random().float(f32); // random t in [0,1]
        const pos = interpolate(curve.start, curve.control, curve.end, t);

        const size = rl.Vector2.init(rng.random().float(f32) * 2.0 + 0.5, // width: 0.5–2.5
            rng.random().float(f32) * 2.0 + 0.5 // height: 0.5–2.5
        );
        const axis = rl.Vector3.init(0.0, rng.random().float(f32) * 2.0 + 0.5, 0.0);
        const angle = rng.random().float(f32) * 90.0;

        result[i] = .{ .position = pos, .size = size, .axis = axis, .angle = angle };
    }

    return result;
}

const Curve3D = struct {
    start: Vector3,
    control: Vector3,
    end: Vector3,

    pub fn generate(rng: *std.Random.DefaultPrng) Curve3D {
        return .{
            .start = randVector3(rng, BOX_MIN, BOX_MAX),
            .control = randVector3(rng, BOX_MIN, BOX_MAX),
            .end = randVector3(rng, BOX_MIN, BOX_MAX),
        };
    }

    pub fn draw(self: Curve3D) void {
        const steps = 32;
        var prev = self.start;

        for (1..steps + 1) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const p = interpolate(self.start, self.control, self.end, t);
            rl.drawLine3D(prev, p, rl.Color.red);
            prev = p;
        }

        // Optional: draw the control points
        rl.drawSphere(self.start, 0.1, rl.Color.blue);
        rl.drawSphere(self.control, 0.1, rl.Color.yellow);
        rl.drawSphere(self.end, 0.1, rl.Color.green);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        arena.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("FAIL");
    }

    std.log.warn("INITIALIZED ALLOCATOR\n", .{});
    rl.initWindow(screen_width, screen_height, "3D Line with Bounding Box");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    zbt.init(arena.allocator());
    defer zbt.deinit();
    var physics_world = zbt.initWorld();

    var current_camera = Camera.perspective;

    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try arena.allocator().create(zbt.DebugDrawer);
    physics_debug.* = zbt.DebugDrawer.init(arena.allocator());
    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(.{ .draw_wireframe = true, .draw_aabb = true });

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    const cameras = init_cameras();
    var curve = Curve3D.generate(&rng);
    var planes = randomPlanes(5, &rng, curve);

    const box_center = rl.Vector3.init(
        (BOX_MIN + BOX_MAX) / 2.0,
        (BOX_MIN + BOX_MAX) / 2.0,
        (BOX_MIN + BOX_MAX) / 2.0,
    );
    const box_size = rl.Vector3.init(
        BOX_MAX - BOX_MIN,
        BOX_MAX - BOX_MIN,
        BOX_MAX - BOX_MIN,
    );

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            curve = Curve3D.generate(&rng);
            planes = randomPlanes(5, &rng, curve);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.p)) {
            current_camera = switch (current_camera) {
                .perspective => .birds_eye,
                .birds_eye => .perspective,
            };
        }
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.dark_gray);

        {
            switch (current_camera) {
                .perspective => rl.beginMode3D(cameras.perspective),
                .birds_eye => rl.beginMode3D(cameras.birds_eye),
            }
            defer rl.endMode3D();
            curve.draw();
            for (planes) |p| {
                p.draw();
            }
            rl.drawCubeWires(box_center, box_size.x, box_size.y, box_size.z, rl.Color.light_gray);
        }

        rl.drawText("Press [R] to regenerate line", 10, 10, 20, rl.Color.white);
    }
}

const std = @import("std");
const engine = @import("engine_core");
const zbt = @import("zbullet");
const rl = @import("raylib");
const LineSegment = engine.util.LineSegment;
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

const Polygon = struct {
    position: Vector3,
    vertices: []Vector3,

    fn draw(self: @This()) void {
        var i: usize = 0;
        while (i < self.vertices.len) : (i += 1) {
            const next_i = (i + 1) % self.vertices.len;

            const v1 = self.vertices[i];
            const v2 = self.vertices[next_i];

            rl.drawLine3D(v2, v1, rl.Color.orange);
            rl.drawTriangle3D(self.position, v2, v1, rl.Color.green);
        }
    }

    fn generateVertices(
        alloc: std.mem.Allocator,
        n: usize,
        position: rl.Vector3,
        rng: *std.Random.DefaultPrng,
        avg_radius: f32,
        irregularity: f32,
        spikiness: f32,
    ) std.mem.Allocator.Error![]rl.Vector3 {
        if (irregularity < 0 or irregularity > 1)
            @panic("Irregularity must be between 0 and 1.");
        if (spikiness < 0 or spikiness > 1)
            @panic("Spikiness must be between 0 and 1.");
        var irr = irregularity;
        var spik = spikiness;
        var vertices = try alloc.alloc(rl.Vector3, n);

        irr *= 2 * std.math.pi / @as(f32, @floatFromInt(n));
        spik *= avg_radius;

        const angle_steps = try randomAngleSteps(alloc, n, rng, irr);

        var angle = rng.random().float(f32) * (2 * std.math.pi);

        // last used is 0 if it was just created
        // 1 if the last one used was `@"0"`
        // 2 if the last one used was `0"1"`
        var last_gauss: struct { vals: struct { f32, f32 }, last_used: u2 } = undefined;
        for (0..n) |i| {
            const v = &vertices[i];
            const step = angle_steps[i];

            const sample = blk: {
                while (true) {
                    switch (last_gauss.last_used) {
                        0 => {
                            last_gauss.last_used += 1;
                            break :blk last_gauss.vals.@"0";
                        },
                        1 => {
                            last_gauss.last_used += 1;
                            break :blk last_gauss.vals.@"1";
                        },
                        else => {
                            last_gauss.vals = engine.noise.generateGaussianNoise(rng, avg_radius, spik);
                            last_gauss.last_used = 0;
                        },
                    }
                }
            };

            const radius: f32 = @min(@max(sample, 0.0), 1.2 * avg_radius);

            const point = rl.Vector3.init(position.x + radius * @cos(angle), position.y, position.z + radius * @sin(angle));
            v.* = point;
            angle += step;
        }
        return vertices;
    }

    fn randomAngleSteps(alloc: std.mem.Allocator, n: usize, rng: *std.Random.DefaultPrng, irregularity: f32) std.mem.Allocator.Error![]f32 {
        var steps = try alloc.alloc(f32, n);
        const lower = (2.0 * std.math.pi / @as(f32, @floatFromInt(steps.len))) - irregularity;
        const upper = (2.0 * std.math.pi / @as(f32, @floatFromInt(steps.len))) + irregularity;
        var cumsum: f32 = 0.0;

        for (0..n) |i| {
            const step = &steps[i];
            const angle = blk: {
                var f = rng.random().float(f32) * upper;
                while (f < lower) {
                    f = rng.random().float(f32) * upper;
                }
                break :blk f;
            };

            step.* = angle;
            cumsum += angle;
        }

        cumsum /= (2 * std.math.pi);
        for (0..n) |i| {
            steps[i] /= cumsum;
        }
        return steps;
    }
};

const ALLOWED_FAILURES = 500;
fn randomPolies(alloc: std.mem.Allocator, n: usize, rng: *std.Random.DefaultPrng, curve: Curve3D) std.mem.Allocator.Error![]Polygon {
    var result = try alloc.alloc(Polygon, n);

    for (0..n) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        const pos = interpolate(curve.start, curve.control, curve.end, t);
        var amt_verts: usize = undefined;
        var verts: []rl.Vector3 = undefined;
        var gen_failures: usize = 0;

        gen_verts: while (true) {
            amt_verts = rng.random().intRangeAtMost(usize, 3, 12);
            verts = try Polygon.generateVertices(alloc, amt_verts, pos, rng, 1, 0.5, 0.2);

            if (i == 0) break :gen_verts;

            const prev_poly = result[i - 1];
            var intersects = false;

            var k: usize = 0;
            while (k < verts.len and !intersects) : (k += 1) {
                const a = verts[k];
                const b = verts[(k + 1) % verts.len];
                const segment = LineSegment{
                    .start = rl.Vector2.init(a.x, a.z),
                    .end = rl.Vector2.init(b.x, b.z),
                };

                var j: usize = 0;
                while (j < prev_poly.vertices.len and !intersects) : (j += 1) {
                    const c = prev_poly.vertices[j];
                    const d = prev_poly.vertices[(j + 1) % prev_poly.vertices.len];
                    const other_segment = LineSegment{
                        .start = rl.Vector2.init(c.x, c.z),
                        .end = rl.Vector2.init(d.x, d.z),
                    };

                    intersects = segment.intersects(other_segment);
                }
            }

            if (!intersects or gen_failures >= ALLOWED_FAILURES) break :gen_verts;
            gen_failures += 1;
            alloc.free(verts);

            std.log.warn(
                \\ intersects, regenerating Polygon 
                \\
            , .{});
        }

        if (gen_failures >= ALLOWED_FAILURES)
            std.log.warn("Failed too many times\n", .{});
        std.log.warn(
            \\ Polygon generated
            \\
        , .{});

        result[i] = Polygon{
            .position = pos,
            .vertices = verts,
        };
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

    var polies = blk: {
        const amt_polies = rng.random().intRangeAtMost(usize, 3, 8);
        break :blk try randomPolies(arena.allocator(), amt_polies, &rng, curve);
    };

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
            // planes = randomPlanes(5, &rng, curve);
            polies = blk: {
                const amt_polies = rng.random().intRangeAtMost(usize, 3, 8);
                break :blk try randomPolies(arena.allocator(), amt_polies, &rng, curve);
            };
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
            for (polies) |p| {
                p.draw();
            }
            rl.drawCubeWires(box_center, box_size.x, box_size.y, box_size.z, rl.Color.light_gray);
        }

        rl.drawText("Press [R] to regenerate line", 10, 10, 20, rl.Color.white);
        rl.drawText("Press [P] to change camera", 10, 40, 20, rl.Color.white);
    }
}

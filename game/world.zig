const rl = @import("raylib");
const std = @import("std");
const engine = @import("engine_core");
const LineSegment = engine.util.LineSegment;
const Vector3 = rl.Vector3;

// World box min and max
pub const BOX_MIN: f32 = -16.0;
pub const BOX_MAX: f32 = 16.0;

pub const World = struct {
    size: f32,
    curve: Curve3D,
    debug_mode: bool = true,
    // polygons: []Polygon,

    /// PROTOTYPING!!!
    /// For now, we will just give every mesh a single heightmap.
    /// Eventually each should be able to have their own
    heightmap: rl.Image,
    meshes: []engine.MeshBundle,
    pub fn generate(allocator: std.mem.Allocator, rng: *std.Random.DefaultPrng, heightmap: rl.Image, world_size: f32) !@This() {
        const amt_polies = rng.random().intRangeAtMost(usize, 3, 8);
        const curve = Curve3D.generate(rng);
        const polygons = try randomNormPolies(allocator, amt_polies, rng, curve);
        defer allocator.free(polygons);

        const meshes = try allocator.alloc(engine.MeshBundle, amt_polies);
        const mesh_size = rl.Vector3.init(
            world_size / 100.0,
            world_size / 100.0,
            world_size / 100.0,
        );

        var material = try rl.loadMaterialDefault();
        material.maps[0].texture = try heightmap.toTexture();
        // material.maps[0].color = rl.Color.ray_white;

        for (polygons, meshes) |p, *m| {
            const transform =
                transform: {
                    var mat = rl.Matrix.identity();
                    mat.m12 = p.position.x;
                    mat.m13 = p.position.y;
                    mat.m14 = p.position.z;
                    break :transform mat;
                };
            var bundle = engine.MeshBundle.init(allocator, transform);
            const idx = try bundle.add_material(material);
            const mesh =
                try engine.terrain.genMaskedImageMesh(allocator, heightmap, mesh_size, p.vertices, 4);
            try bundle.add_mesh(mesh, idx);
            m.* = bundle;
        }

        return @This(){
            .curve = curve,
            .heightmap = heightmap,
            .meshes = meshes,
            .size = world_size,
        };
    }

    /// Should be called with the same allocator used to `generate`
    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        // _ = allocator;
        allocator.free(self.meshes);
        rl.unloadImage(self.heightmap);
        // for (self.meshes) |*m| {
        //     m.deinit();
        //     rl.unloadMesh(m);
        // }
    }

    /// Maybe this should just return a texture rather than using raylib to render
    pub fn renderHeightmapTexture(self: @This(), allocator: std.mem.Allocator) !void {
        const size: usize = 512;
        const tex = try rl.RenderTexture2D.init(size, size);

        const range_x: f32 = BOX_MAX - BOX_MIN;
        const range_y: f32 = BOX_MAX - BOX_MIN;
        const padding: f32 = 10.0; // pixels of border around the shape
        const scale_x: f32 = (size - 2.0 * padding) / range_x;
        const scale_y: f32 = (size - 2.0 * padding) / range_y;
        const scale: f32 = @min(scale_x, scale_y);

        _ = scale;
        _ = self;
        _ = allocator;

        {
            rl.beginTextureMode(tex);
            defer rl.endTextureMode();
            rl.clearBackground(rl.Color.black);
            rl.drawText("TOP RIGHT", size - 70, 0, 10, rl.Color.white);
            rl.drawText("TOP LEFT", 0, 0, 10, rl.Color.white);
            rl.drawText("BOTTOM RIGHT", size - 90, size - 10, 10, rl.Color.white);
            rl.drawText("BOTTOM LEFT", 0, size - 10, 10, rl.Color.white);

            // for (self.meshes) |mesh| {
            //     const vert_count = poly.vertices.len;
            //     std.debug.assert(vert_count >= 3);
            //     const screen_vertices = try allocator.alloc(rl.Vector2, vert_count + 2); // +1 for center, +1 to close loop
            //     defer allocator.free(screen_vertices);

            //     // Center point of fan (convert to image space)
            //     screen_vertices[0] = rl.Vector2{
            //         .x = (poly.position.x - BOX_MIN) * scale + padding,
            //         .y = size - ((poly.position.z - BOX_MIN) * scale + padding), // flip Y
            //     };

            //     // Add polygon points in order
            //     for (poly.vertices, 0..) |v, i| {
            //         screen_vertices[i + 1] = rl.Vector2{
            //             .x = (v.x - BOX_MIN) * scale + padding,
            //             .y = size - ((v.z - BOX_MIN) * scale + padding),
            //         };
            //     }

            //     // Close the fan loop (optional, Raylib may not need this depending on API version)
            //     screen_vertices[vert_count + 1] = screen_vertices[1];

            //     rl.drawTriangleFan(screen_vertices, rl.Color.red);

            //     // Optional: draw dots for debugging
            //     // for (screen_vertices) |pt| {
            //     //     rl.drawCircleV(pt, 2.0, rl.Color.green);
            //     // }

            // }
        }

        rl.drawTextureRec(
            tex.texture,
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
};

fn randVector3(rng: *std.Random.DefaultPrng, min: f32, max: f32) Vector3 {
    return .{
        .x = rng.random().float(f32) * (max - min) + min,
        .y = rng.random().float(f32) * (max - min) + min,
        .z = rng.random().float(f32) * (max - min) + min,
    };
}

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

/// Precursor to terrain mesh
pub const TerrainPolygon = struct {
    /// This is the position the mesh should be in
    position: Vector3,
    /// This defines the polygon mask where the mesh is generated
    /// MUST be defined in normalized space
    /// (-1 : 1)
    vertices: []rl.Vector2,

    /// should be called with the same allocator used to `generateVertices`
    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
    }
};

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

fn generateNormalizedVertices(
    alloc: std.mem.Allocator,
    rng: *std.Random.DefaultPrng,
    options: struct {
        n_verts: usize,
        /// MUST be between 0 and 1
        irregularity: f32,
        /// MUST be between 0 and 1
        spikiness: f32,
    },
) std.mem.Allocator.Error![]rl.Vector2 {
    if (options.irregularity < 0 or options.irregularity > 1)
        @panic("options.Irregularity must be between 0 and 1.");
    if (options.spikiness < 0 or options.spikiness > 1)
        @panic("options.Spikiness must be between 0 and 1.");

    var irr = options.irregularity;
    var vertices = try alloc.alloc(rl.Vector2, options.n_verts);

    irr *= 2 * std.math.pi / @as(f32, @floatFromInt(options.n_verts));

    const angle_steps = try randomAngleSteps(alloc, options.n_verts, rng, irr);
    defer alloc.free(angle_steps);

    var angle = rng.random().float(f32) * (2 * std.math.pi);

    // last used is 0 if it was just created
    // 1 if the last one used was `@"0"`
    // 2 if the last one used was `0"1"`
    // If 2, we sample again & set `last_used` to 0
    // Doing this as a naive way of keeping track of which value we sampled last because we are
    // sampling the noise two values at a time
    // ... I'm sure there's a better way
    var last_gauss: struct { vals: struct { f32, f32 }, last_used: u2 } = undefined;
    for (0..options.n_verts) |i| {
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
                        last_gauss.vals = engine.noise.sampleNormalPair(rng, 1.0, options.spikiness);
                        last_gauss.last_used = 0;
                    },
                }
            }
        };

        // Radius is clamped to 1.0 to ensure normalized values
        const radius: f32 = @min(@max(sample, 0.0), 1.0);

        const point = rl.Vector2.init(radius * @cos(angle), radius * @sin(angle));
        v.* = point;
        angle += step;
    }
    return vertices;
}

const ALLOWED_FAILURES = 500;
/// Generates random polygons along curve
/// Vertices defined in normalized space
fn randomNormPolies(alloc: std.mem.Allocator, amt: usize, rng: *std.Random.DefaultPrng, curve: Curve3D) std.mem.Allocator.Error![]TerrainPolygon {
    var result = try alloc.alloc(TerrainPolygon, amt);

    for (0..amt) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(amt - 1));
        const pos = interpolate(curve.start, curve.control, curve.end, t);
        var amt_verts: usize = undefined;
        var verts: []rl.Vector2 = undefined;
        var gen_failures: usize = 0;

        gen_verts: while (true) {
            amt_verts = rng.random().intRangeAtMost(usize, 3, 12);
            // verts = try Polygon.generateVertices(alloc, amt_verts, pos, rng, 1, 0.5, 0.2);
            verts = try generateNormalizedVertices(alloc, rng, .{ .n_verts = amt_verts, .irregularity = 0.5, .spikiness = 0.2 });

            if (i == 0) break :gen_verts;

            const prev_poly = result[i - 1];
            var intersects = false;

            var k: usize = 0;
            while (k < verts.len and !intersects) : (k += 1) {
                const a = verts[k];
                const b = verts[(k + 1) % verts.len];
                const segment = LineSegment{
                    .start = rl.Vector2.init(a.x, a.y),
                    .end = rl.Vector2.init(b.x, b.y),
                };

                var j: usize = 0;
                while (j < prev_poly.vertices.len and !intersects) : (j += 1) {
                    const c = prev_poly.vertices[j];
                    const d = prev_poly.vertices[(j + 1) % prev_poly.vertices.len];
                    const other_segment = LineSegment{
                        .start = rl.Vector2.init(c.x, c.y),
                        .end = rl.Vector2.init(d.x, d.y),
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

        result[i] = TerrainPolygon{
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

        rl.drawSphere(self.start, 0.1, rl.Color.blue);
        rl.drawSphere(self.control, 0.1, rl.Color.yellow);
        rl.drawSphere(self.end, 0.1, rl.Color.green);
    }
};

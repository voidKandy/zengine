const std = @import("std");
const ui = @import("raygui");
const engine = @import("engine_core");
const game = @import("game_core");
const Ecs = game.Ecs;
const zbt = @import("zbullet");
const rl = @import("raylib");
const LineSegment = engine.util.LineSegment;
const Vector3 = rl.Vector3;
// const Polygon = game.world.Polygon;
// const Curve3D = game.world.Curve3D;

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

/// COPY PASTE Of RotateD6System
pub const RotateTerrain = Ecs.System{
    .queries = &[_]Ecs.Query{
        Ecs.Query{
            .query = .{
                .is = Ecs.QueryStatement.new(
                    .at_least,
                    &[_]Ecs.ComponentsTag{.bundle},
                ),
            },
        },
    },
    .schedule = .automatic,
    .runFn = struct {
        fn run(results: []Ecs.QueryResult, myecs: *Ecs, state: *game.state.GameState) void {
            const dt = rl.getFrameTime();
            const rotation = rl.Matrix.rotateXYZ(rl.Vector3{
                // .x = 2.0 * dt,
                .x = 0.0,
                .y = 0.5 * dt,
                .z = 0.0,
                // .y = 0.5 * dt,
                // .z = 1.5 * dt,
            });

            const e = results[0].query[0];
            const idx = myecs.entities.manager.index_map.get(e) orelse @panic("NO IDX?");
            std.log.warn("Got idx: {d}\n", .{idx});
            const bundle = myecs.components.access(engine.MaterialMesh, .bundle, idx) orelse @panic("NO BUNDLE?");

            bundle.transform = rl.Matrix.multiply(rotation, bundle.transform);
            _ = state;
        }
    }.run,
};

fn initState(allocator: std.mem.Allocator, ecs: *Ecs) !game.state.GameState {
    var physics_world = zbt.initWorld();

    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try allocator.create(zbt.DebugDrawer);
    physics_debug.* = zbt.DebugDrawer.init(allocator);
    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(.{ .draw_wireframe = true, .draw_aabb = true });

    const camera = rl.Camera{
        .position = rl.Vector3.init(18.0, 21.0, 18.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    };

    var handle = try ecs.entities.register();
    try handle.addComponent(.camera, camera);
    // const sys_id, _ = try ecs.systems.register(game.cameras.ORBITAL_CAMERA_SYSTEM);

    var cameras = std.ArrayList(game.state.CameraReference).init(allocator);
    try cameras.append(game.state.CameraReference{
        .camera_id = handle.identifier,
        // .system_id = sys_id,
    });

    const state = game.state.GameState{
        .window_height = WINDOW_HEIGHT,
        .window_width = WINDOW_WIDTH,
        .current_camera = 0,
        .cameras = cameras,
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
    };
    return state;
}

pub fn MeshManipulation(mesh_id: engine.ecs.Entity) Ecs.System {
    Ecs.System{
        .queries = &[_]Ecs.Query{
            Ecs.Query{ .id = mesh_id },
        },
        .runFn = struct {
            fn run(results: []Ecs.QueryResult, myecs: *Ecs, state: *game.state.GameState) void {
                const e = results[0].query[0];
                const idx = myecs.entities.manager.index_map.get(e) orelse @panic("NO IDX?");
                std.log.warn("Got idx: {d}\n", .{idx});
                const bundle = myecs.components.access(engine.MaterialMesh, .bundle, idx) orelse @panic("NO BUNDLE?");
                _ = bundle;
                // bundle.meshes.items[0] =
            }
        }.run,
    };
}

fn createNoiseImage(seed: u32, size: i32, scale: f32) !rl.Image {
    var img = rl.Image.genColor(size, size, rl.Color.black);
    engine.noise.genPerlinNoise(&img, seed, scale);

    return img;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Terrain");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ecs = Ecs.init(&arena);
    defer ecs.deinit();
    zbt.init(arena.allocator());
    defer zbt.deinit();
    var state = try initState(arena.allocator(), &ecs);
    defer state.deinit();
    _ = try ecs.systems.register(RotateTerrain);

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const size: i32 = 512;
    const seed = rng.random().int(u32);
    var scale: f32 = 0.009;
    var last_scale = scale;
    var image = try createNoiseImage(seed, size, scale);
    // const render_tex = try rl.RenderTexture2D.init(size, size);

    const mask = &[_]rl.Vector2{
        // .{
        //     .x = 0.0,
        //     .y = 0.0,
        // },
        .{ .x = 0.5, .y = 0.5 },
        .{ .x = -0.5, .y = 0.5 },
        // .{ .x = -0.7, .y = 0.0 },
        .{ .x = -0.5, .y = -0.5 },
        .{ .x = 0.5, .y = -0.5 },
        .{ .x = 0.5, .y = 0.5 },
    };
    var texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);

    // this is the rectangle that represents the texture to be mapped over the mask
    const rect_w: i32 = texture.width;
    const rect_h: i32 = texture.height;

    // WINDOW_WIDTH - texture.width - 20, 20
    const rect_x: i32 = WINDOW_WIDTH - texture.width - 20;
    // const rect_y: i32 = WINDOW_HEIGHT / 2 - @divTrunc(rect_h, 2) - texture.width - 20;
    const rect_y = 20;

    // We need to translate the normalized mask into screen space based on the position of the rectangle defined above
    var screen_mask: [mask.len]rl.Vector2 = undefined;

    for (mask, 0..) |v, i| {
        const rect_x_fl: f32 = @floatFromInt(rect_x);
        const rect_y_fl: f32 = @floatFromInt(rect_y);
        const rect_w_fl: f32 = @floatFromInt(rect_w);
        const rect_h_fl: f32 = @floatFromInt(rect_h);

        // Three steps to translating:
        // _First_: Add 1.0 to normalized coordinates (because -1.0 and 1.0 are the lower and upper bounds of our norm space)
        // _Second_: Divide the result of step one by 2 to renormalize w/out any negatives
        // _Third_: Subtract the resulting Y value from 1.0 (because the Y needs to be flipped to align with raylib)
        const translated_x = (v.x + 1.0) / 2.0;
        const translated_y = 1.0 - ((v.y + 1.0) / 2.0);
        screen_mask[i] = rl.Vector2{
            .x = rect_x_fl + translated_x * rect_w_fl,
            .y = rect_y_fl + translated_y * rect_h_fl,
        };
    }

    const mesh_size =
        rl.Vector3.init(16.0, 8.0, 16.0);

    var mesh = try engine.terrain.genMaskedImageMesh(arena.allocator(), image, mesh_size, mask, 2);
    // var mesh = try genMaskedImageMesh(arena.allocator(), image, mesh_size, null, 16);

    var material = try rl.loadMaterialDefault();
    // material.maps[0].color = rl.Color.ray_white;
    material.maps[0].texture = texture;

    var position = rl.Matrix.identity();
    position.m12 = -8.0;
    position.m14 = -8.0;

    var bundle =
        engine.MaterialMesh.init(ecs.allocator, position);
    const idx = try bundle.add_material(material);
    try bundle.add_mesh(mesh, idx);
    var entity = try ecs.entities.register();

    try entity.addComponent(.bundle, bundle);

    while (!rl.windowShouldClose()) {
        try ecs.runSystems(&state);
        try state.update(&ecs);
        if (rl.isKeyPressed(rl.KeyboardKey.r) or last_scale != scale) {
            // seed = rng.random().int(u32);
            image = try createNoiseImage(seed, size, scale);
            texture = try image.toTexture();
            mesh = try engine.terrain.genMaskedImageMesh(arena.allocator(), image, mesh_size, mask, 2);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        rl.drawTexture(texture, WINDOW_WIDTH - texture.width - 20, 20, rl.Color.white);
        rl.drawRectangleLines(rect_x, rect_y, rect_w, rect_h, rl.Color.green);
        try state.draw(&ecs);
        // rl.drawTriangleFan(mask, rl.Color.red);

        // rl.drawTriangleStrip(&screen_mask, rl.Color.red);
        // rl.drawTriangleFan(&screen_mask, rl.Color.red);

        last_scale = scale;
        _ = ui.guiSliderBar(
            rl.Rectangle{ .x = 10, .y = 10, .width = 200, .height = 20 },
            "Min",
            "Max",
            &scale,
            0.0,
            0.1,
        );
        rl.drawFPS(10, 10);
    }
}

//
// ---
// # Terrain stuff
//      !WIP!
//  likely should be abstracted later
//

/// Outermost mesh generation from Image
/// Should not create vertices where the pixel alpha == 0
fn genMaskedImageMesh(
    allocator: std.mem.Allocator,
    heightmap: rl.Image,
    size: rl.Vector3,
    mask: ?[]rl.Vector2,
    sampling_resolution: usize,
) !rl.Mesh {
    _ = sampling_resolution;
    _ = mask;
    const width: usize = @intCast(heightmap.width);
    const height: usize = @intCast(heightmap.height);

    const colors = try rl.loadImageColors(heightmap);

    defer rl.unloadImageColors(colors);

    const step_x: f32 = (size.x / @as(f32, @floatFromInt(width - 1)));
    const step_z: f32 = size.z / @as(f32, @floatFromInt(height - 1));

    var vertices = std.ArrayList(rl.Vector3).init(allocator);
    // defer vertices.deinit();

    var normals = std.ArrayList(rl.Vector3).init(allocator);
    // defer normals.deinit();

    var uvs = std.ArrayList(rl.Vector2).init(allocator);
    // defer uvs.deinit();

    var indices = std.ArrayList(u16).init(allocator);
    // defer indices.deinit();

    for (0..height) |z_idx| {
        for (0..width) |x_idx| {
            const idx00 = .{ x_idx, z_idx };
            const idx10 = .{ x_idx + 1, z_idx };
            const idx01 = .{ x_idx, z_idx + 1 };
            const idx11 = .{ x_idx + 1, z_idx + 1 };

            const color = avg: {
                // var c = rl.Color.black;
                var c_r: u32 = 0;
                var c_g: u32 = 0;
                var c_b: u32 = 0;
                // var c_a: u32 = 0;
                for (&[_]struct { usize, usize }{ idx00, idx10, idx01, idx11 }) |idcs| {
                    const x, const z = idcs;
                    const clamped_x = @min(x, width - 1);
                    const clamped_z = @min(z, height - 1);
                    const idx = clamped_z * width + clamped_x;
                    const pixel = colors[idx];
                    c_r += @intCast(pixel.r);
                    c_g += @intCast(pixel.g);
                    c_b += @intCast(pixel.b);
                    // c.a += pixel.a;
                }
                c_r /= 4;
                c_g /= 4;
                c_b /= 4;

                // c.a += 4;
                break :avg rl.Color{ .r = @intCast(c_r), .g = @intCast(c_g), .b = @intCast(c_b), .a = 255 };
            };

            // if (color.a == 0 and
            //     color.r == rl.Color.black.r and
            //     color.g == rl.Color.black.g and
            //     color.b == rl.Color.black.b) continue;

            const height_value = @as(f32, @floatFromInt(color.r)) / 255.0;
            const y = height_value * size.y;

            const x = @as(f32, @floatFromInt(x_idx)) * step_x;
            const z = @as(f32, @floatFromInt(z_idx)) * step_z;

            try vertices.append(.{ .x = x, .y = y, .z = z });
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(.{
                .x = @as(f32, @floatFromInt(x_idx)) / @as(f32, @floatFromInt(width - 1)),
                .y = @as(f32, @floatFromInt(z_idx)) / @as(f32, @floatFromInt(height - 1)),
            });
        }
    }

    // Generate indices for triangle grid
    for (0..height - 1) |z_idx| {
        for (0..width - 1) |x_idx| {
            const i_0: u16 = @intCast(z_idx * width + x_idx);
            const i_1: u16 = @intCast(z_idx * width + x_idx + 1);
            const i_2: u16 = @intCast((z_idx + 1) * width + x_idx);
            const i_3: u16 = @intCast((z_idx + 1) * width + x_idx + 1);

            // Triangle 1
            try indices.append(i_0);
            try indices.append(i_2);
            try indices.append(i_1);

            // Triangle 2
            try indices.append(i_1);
            try indices.append(i_2);
            try indices.append(i_3);
        }
    }

    // Allocate Mesh
    var mesh = try allocator.create(rl.Mesh);
    mesh.* = std.mem.zeroInit(rl.Mesh, .{});

    // Assign data
    mesh.*.vertices = @as([*]f32, @ptrCast(try allocator.alloc(f32, vertices.items.len * 3)));
    mesh.*.normals = @as([*]f32, @ptrCast(try allocator.alloc(f32, normals.items.len * 3)));
    mesh.*.texcoords = @as([*]f32, @ptrCast(try allocator.alloc(f32, uvs.items.len * 2)));
    mesh.*.indices = @as([*]u16, @ptrCast(try allocator.alloc(u16, indices.items.len)));

    // Fill vertex data
    for (vertices.items, 0..) |v, i| {
        mesh.vertices[i * 3 + 0] = v.x;
        mesh.vertices[i * 3 + 1] = v.y;
        mesh.vertices[i * 3 + 2] = v.z;
    }
    for (normals.items, 0..) |n, i| {
        mesh.normals[i * 3 + 0] = n.x;
        mesh.normals[i * 3 + 1] = n.y;
        mesh.normals[i * 3 + 2] = n.z;
    }
    for (uvs.items, 0..) |uv, i| {
        mesh.texcoords[i * 2 + 0] = uv.x;
        mesh.texcoords[i * 2 + 1] = uv.y;
    }
    std.mem.copyForwards(u16, mesh.indices[0..indices.items.len], indices.items);

    mesh.*.vertexCount = @as(c_int, @intCast(vertices.items.len));
    mesh.*.triangleCount = @as(c_int, @intCast(indices.items.len / 3));

    std.log.warn(
        \\ MESH GENERATED: {any}
        \\
    , .{mesh});

    return mesh.*;
}

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

const RotateMeshSystem = struct {
    mesh_id: engine.Entity,

    pub fn run(self: *@This(), myecs: *Ecs, state: *game.state.GameState) anyerror!void {
        std.log.warn(
            \\ INNER MESH
            \\ {d}
        , .{self.mesh_id});
        const dt = rl.getFrameTime();
        var handle = try myecs.entityHandle(self.mesh_id);
        const mat_mesh = try handle.accessComponent(engine.MaterialMesh, .material_mesh);
        const rotation = rl.Matrix.rotateXYZ(rl.Vector3{
            .x = 0.0,
            .y = 0.5 * dt,
            .z = 0.0,
            // .y = 0.5 * dt,
            // .z = 1.5 * dt,
        });

        mat_mesh.transform = rl.Matrix.multiply(rotation, mat_mesh.transform);
        _ = state;
    }
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
    try handle.addComponent(.camera3D, camera);
    // const sys_id, _ = try ecs.systems.register(game.cameras.ORBITAL_CAMERA_SYSTEM);

    var cameras = std.ArrayList(game.state.EcsCameraReference).init(allocator);
    try cameras.append(game.state.EcsCameraReference{
        .id = handle.identifier,
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

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const noise = try allocator.create(engine.noise.Noise);
    noise.* = engine.noise.Noise{
        .size = 512,
        .seed = rng.random().int(u32),
        .scale = 0.009,
    };

    // we pass this id to a few systems
    var mesh_id: engine.Entity = undefined;
    {
        const a, const b, const c = .{
            try ecs.entities.register(),
            try ecs.entities.register(),
            try ecs.entities.register(),
        };

        const noise_system =
            game.systems.EditNoiseSystem{
                .noise = noise.*,
                .mesh = a.identifier,
                .image = b.identifier,
                .ui = c.identifier,
            };
        mesh_id = noise_system.mesh;
        std.log.warn(
            \\ MESH
            \\ {d}
        , .{mesh_id});
        const edit_noise_system = try Ecs.System.init(ecs.allocator, game.systems.EditNoiseSystem, noise_system);

        const id, _ = try ecs.registerSystem(edit_noise_system, .pre_render);
        try ecs.startSytem(id);
    }

    std.log.warn(
        \\ MESH
        \\ {d}
    , .{mesh_id});
    const rotate_system = try Ecs.System.init(ecs.allocator, RotateMeshSystem, .{ .mesh_id = mesh_id });
    _ = try ecs.registerSystem(rotate_system, .pre_render);
    const draw_system = try Ecs.System.init(ecs.allocator, game.systems.DrawSystem, .{});
    _ = try ecs.registerSystem(draw_system, .render);

    try ecs.startSytems();

    while (!rl.windowShouldClose()) {
        try ecs.runSystems(&state);
        // _ = ui.guiSliderBar(
        //     rl.Rectangle{ .x = 10, .y = 10, .width = 200, .height = 20 },
        //     "Min",
        //     "Max",
        //     &noise.scale,
        //     0.0,
        //     0.1,
        // );
        // rl.drawFPS(10, 10);
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

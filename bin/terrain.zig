const std = @import("std");
const engine = @import("engine_core");
const game = @import("game_core");
const zbt = @import("zbullet");
const rl = @import("raylib");
const LineSegment = engine.util.LineSegment;
const Vector3 = rl.Vector3;
// const Polygon = game.world.Polygon;
// const Curve3D = game.world.Curve3D;

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

fn initState(allocator: std.mem.Allocator, ecs: *game.Ecs) !game.state.GameState {
    const camera = rl.Camera{
        .position = rl.Vector3.init(18.0, 21.0, 18.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    };

    var handle = try ecs.entities.register();
    try handle.addComponent(.camera, camera);
    const sys_id, _ = try ecs.systems.register(game.cameras.ORBITAL_CAMERA_SYSTEM);

    var cameras = std.ArrayList(game.state.CameraReference).init(allocator);
    try cameras.append(game.state.CameraReference{
        .camera_id = handle.identifier,
        .system_id = sys_id,
    });

    const state = game.state.GameState{
        .window_height = WINDOW_HEIGHT,
        .window_width = WINDOW_WIDTH,
        .current_camera = 0,
        .cameras = cameras,
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

    var ecs = game.Ecs.init(&arena);
    defer ecs.deinit();
    var state = try initState(arena.allocator(), &ecs);
    defer state.deinit();

    const image = try rl.loadImage("resources/heightmap.png");
    defer rl.unloadImage(image);

    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);

    var mesh = try genMeshHeightmap(arena.allocator(), image, rl.Vector3.init(16.0, 8.0, 16.0));

    rl.uploadMesh(&mesh, true);
    // defer rl.unloadMesh(mesh);

    var material = try rl.loadMaterialDefault();
    material.maps[0].texture = texture;
    var position = rl.Matrix.identity();
    position.m12 = -8.0;
    position.m14 = -8.0;

    var bundle =
        engine.MeshBundle.init(ecs.allocator, &[_]rl.Material{material}, position);
    try bundle.add(mesh, 0);

    var entity = try ecs.entities.register();

    try entity.addComponent(.bundle, bundle);

    while (!rl.windowShouldClose()) {
        try ecs.runSystems(&state);
        try state.update(&ecs);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        defer rl.endDrawing();

        try state.draw(&ecs);

        rl.drawTexture(texture, WINDOW_WIDTH - texture.width - 20, 20, rl.Color.white);
        rl.drawRectangleLines(WINDOW_WIDTH - texture.width - 20, 20, texture.width, texture.height, rl.Color.green);

        rl.drawFPS(10, 10);
    }
}

fn genMeshHeightmap(
    allocator: std.mem.Allocator,
    heightmap: rl.Image,
    size: rl.Vector3,
) !rl.Mesh {
    const width: usize = @intCast(heightmap.width);
    const height: usize = @intCast(heightmap.height);

    const colors = try rl.loadImageColors(heightmap);
    defer rl.unloadImageColors(colors);

    // Precompute scaling
    const step_x: f32 = size.x / @as(f32, @floatFromInt(width - 1));
    const step_z: f32 = size.z / @as(f32, @floatFromInt(height - 1));

    // Arrays for mesh data
    var vertices = std.ArrayList(rl.Vector3).init(allocator);
    // defer vertices.deinit();

    var normals = std.ArrayList(rl.Vector3).init(allocator);
    // defer normals.deinit();

    var uvs = std.ArrayList(rl.Vector2).init(allocator);
    // defer uvs.deinit();

    var indices = std.ArrayList(u16).init(allocator);
    // defer indices.deinit();

    // Generate vertices, normals, uvs
    for (0..height) |z_idx| {
        for (0..width) |x_idx| {
            const idx = z_idx * width + x_idx;
            const pixel = colors[idx];

            const height_value = @as(f32, @floatFromInt(pixel.r)) / 255.0;
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

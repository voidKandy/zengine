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

    var image = try rl.loadImage("resources/heightmap.png");
    defer rl.unloadImage(image);
    std.log.warn(
        \\ IMAGE FORMAT: {any}
        \\
    , .{image.format});

    rl.imageFormat(&image, rl.PixelFormat.uncompressed_r8g8b8a8);

    const mask = &[_]rl.Vector2{

        //     rl.Vector2{
        //     .x = 0.0,
        //     .y = 0.0,
        // },

        rl.Vector2{
            .x = 0.5,
            .y = 0.5,
        },
        rl.Vector2{
            .x = -0.5,
            .y = 0.5,
        },
        rl.Vector2{
            .x = -0.5,
            .y = -0.5,
        },
        rl.Vector2{
            .x = 0.5,
            .y = -0.5,
        },
    };

    {
        const width: usize = @intCast(image.width);
        const height: usize = @intCast(image.height);

        var pixels = @as([*]rl.Color, @ptrCast(image.data));

        // Build your polygon vertex list in mask space
        var mask_vertices = std.ArrayList(rl.Vector2).init(allocator);
        defer mask_vertices.deinit();

        // Masks, defined in normalized space, need to be translated to pixel space for accurate mapping over the original image
        for (mask) |v| {
            try mask_vertices.append(rl.Vector2{
                .x = ((v.x * 0.5) + 0.5) * @as(f32, @floatFromInt(width - 1)),
                .y = ((-v.y * 0.5) + 0.5) * @as(f32, @floatFromInt(height - 1)), // <-- flip Y!
            });
        }

        // Loop through every pixel
        for (0..height) |y_px| {
            for (0..width) |x_px| {
                const p = rl.Vector2{
                    .x = @floatFromInt(x_px),
                    .y = @floatFromInt(y_px),
                };

                if (!engine.util.pointInPolygon(p, mask_vertices.items)) {
                    const idx = y_px * width + x_px;
                    pixels[idx] = rl.Color.black;
                    pixels[idx].a = 0;
                }
            }
        }
    }

    const texture = try rl.loadTextureFromImage(image);
    defer rl.unloadTexture(texture);

    const mesh_size =
        rl.Vector3.init(16.0, 8.0, 16.0);
    var mesh = try genMaskedImageMesh(arena.allocator(), image, mesh_size, null, 16);

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
        rl.drawTriangleFan(mask, rl.Color.red);
        rl.drawRectangleLines(WINDOW_WIDTH - texture.width - 20, 20, texture.width, texture.height, rl.Color.green);

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

            if (color.a == 0) continue;

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

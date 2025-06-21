const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const engine = @import("engine_core");
const game = @import("game_core");
const zm = @import("zmath");

const warn = std.log.warn;
const Vector3 = rl.Vector3;

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 450;

fn initState(allocator: std.mem.Allocator, ecs: *game.Ecs) !game.state.GameState {
    const camera = rl.Camera{
        .position = rl.Vector3.init(0.0, 2.0, 4.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    };
    const transform = rl.Matrix.identity();

    const bundle = engine.CameraBundle.init(camera, transform);

    var handle = try ecs.entities.register();
    try handle.addComponent(.camera, bundle);

    const system = game.Ecs.System{
        .schedule = .explicit,
        .queries = &[_]game.Ecs.Query{.{ .id = handle.identifier }},
        .runFn = struct {
            fn run(results: []game.Ecs.QueryResult, myecs: *game.Ecs, st: *game.state.GameState) void {
                const camera_id = results[0].id;
                const idx = myecs.entities.manager.index_map.get(camera_id) orelse @panic("CAMERA ENTITY DOES NOT EXIST??");
                const cam = myecs.components.access(engine.CameraBundle, .camera, idx) orelse @panic("CAMERA BUNDLE DOES NOT EXIST??");
                _ = cam;
                _ = st;
            }
        }.run,
    };
    const sys_id, _ = try ecs.systems.register(system);

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

pub const RotateD6System = game.Ecs.System{
    .queries = &[_]game.Ecs.Query{
        game.Ecs.Query{
            .query = .{
                .is = game.Ecs.QueryStatement.new(
                    .at_least,
                    &[_]game.Ecs.ComponentsTag{.bundle},
                ),
            },
        },
    },
    .schedule = .automatic,
    .runFn = struct {
        fn run(results: []game.Ecs.QueryResult, myecs: *game.Ecs, state: *game.state.GameState) void {
            const dt = rl.getFrameTime();
            const rotation = rl.Matrix.rotateXYZ(rl.Vector3{
                .x = 2.0 * dt,
                .y = 2.0 * dt,
                .z = 0.5 * dt,
            });

            const e = results[0].query[0];
            const idx = myecs.entities.manager.index_map.get(e) orelse @panic("NO IDX?");
            std.log.warn("Got idx: {d}\n", .{idx});
            const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx) orelse @panic("NO BUNDLE?");

            bundle.transform = rl.Matrix.multiply(rotation, bundle.transform);
            _ = state;
        }
    }.run,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Dice");
    defer rl.closeWindow();

    var ecs = game.Ecs.init(&arena);
    defer ecs.deinit();
    _ = try ecs.systems.register(RotateD6System);

    zbt.init(arena.allocator());
    defer zbt.deinit();

    var state = try initState(arena.allocator(), &ecs);
    defer state.deinit();
    std.log.warn("STATE STORED: {any}", .{state.cameras});

    const numbers_atlas_texture = rl.loadTexture("resources/numbers.png") catch @panic("COULD NOT GET TEXTURE FROM ATLAS IMAGE");

    const d6_entity = blk: {
        var d6_inner_material = try rl.loadMaterialDefault();
        const shader = try rl.loadShader("resources/shaders/basic.vs", "resources/shaders/basic.fs");
        if (shader.id == 0) {
            @panic("SHADER FAILED TO LOAD");
        }
        d6_inner_material.shader = shader;
        var d6_world_transform = rl.Matrix.identity();
        const d6_size = 1.0;
        d6_world_transform.m14 -= 0.5;

        const d6_inner_mesh = rl.genMeshCube(d6_size, d6_size, d6_size);
        const d6_faces = try game.dice.genD6Faces(ecs.allocator, d6_size * 1.01);

        var d6_face_material = try rl.loadMaterialDefault();
        d6_face_material.maps[0].texture = numbers_atlas_texture;

        var entity = try ecs.entities.register();
        var d6_bundle =
            engine.MeshBundle.init(ecs.allocator, &[_]rl.Material{ d6_inner_material, d6_face_material }, d6_world_transform);
        try d6_bundle.add(d6_inner_mesh, 0);
        for (d6_faces) |mesh| {
            try d6_bundle.add(mesh, 1);
        }
        try entity.addComponent(.bundle, d6_bundle);
        break :blk entity;
    };

    _ = d6_entity;

    std.log.warn("STATE STORED: {any}", .{state.cameras});
    try state.update(&ecs);
    std.log.warn("STATE STORED: {any}", .{state.cameras});

    while (!rl.windowShouldClose()) {
        try ecs.runSystems(&state);
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        defer rl.endDrawing();
        // draw
        //
        try state.draw(&ecs);
    }
}

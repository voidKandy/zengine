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
/// assumes `zbt.init()` has been called
fn initScene() game.Ecs.Scene {
    var scene = game.Ecs.Scene.init(game.cameras.CameraArchetype);

    const camera = rl.Camera{
        .position = rl.Vector3.init(0.0, 2.0, 4.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    };
    const bundle = game.Ecs.Scene.CameraBundle{ .camera = camera, .system = .{
        game.Ecs.Query{},
        struct {
            fn run(cam: rl.Camera3D, entities: []engine.ecs.Entity, myecs: *game.Ecs, st: *game.Ecs.State) void {
                _ = cam;
                _ = entities;
                _ = myecs;
                _ = st;
            }
        }.run,
    } };
    scene.addCamera(bundle);
    return scene;
}

pub const RotateD6System = game.Ecs.System{ .query = game.Ecs.Query{ .is = game.Ecs.QueryStatement.new(.at_least, &[_]game.Ecs.ComponentsTag{.bundle}) }, .runFn = struct {
    fn run(entities: []engine.ecs.Entity, myecs: *game.Ecs, state: *game.state.GameState) void {
        const dt = rl.getFrameTime();
        const rotation = rl.Matrix.rotateXYZ(rl.Vector3{
            .x = 2.0 * dt,
            .y = 2.0 * dt,
            .z = 0.5 * dt,
        });

        const e = entities[0];
        const idx = myecs.entities.manager.index_map.get(e) orelse @panic("NO IDX?");
        std.log.warn("Got idx: {d}\n", .{idx});
        const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx) orelse @panic("NO BUNDLE?");

        bundle.transform = rl.Matrix.multiply(rotation, bundle.transform);
        _ = state;
    }
}.run };

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

    const state = game.state.GameState{
        .window_height = WINDOW_HEIGHT,
        .window_width = WINDOW_WIDTH,
    };
    defer state.deinit();
    var scene = initScene();

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

    while (!rl.windowShouldClose()) {
        try ecs.runSystems(&scene);
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);
        defer rl.endDrawing();
        const camera =
            scene.currentCamera().?.camera;
        // draw
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            rl.drawGrid(10, 1.0);
            for (0..ecs.entities.manager.count) |idx| {
                if (ecs.components.access(engine.MeshBundle, .bundle, idx)) |access_bundle| {
                    access_bundle.draw();
                }
            }
        }
    }
}

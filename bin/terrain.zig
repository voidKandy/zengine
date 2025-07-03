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

    const mesh = rl.genMeshHeightmap(image, rl.Vector3.init(16.0, 8.0, 16.0));
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

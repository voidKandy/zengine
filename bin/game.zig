const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const engine = @import("engine_core");
const game = @import("game_core");
const zm = @import("zmath");
const Vector3 = rl.Vector3;
const Ecs = game.GameEcs;

const WINDOW_WIDTH = 1600;
const WINDOW_HEIGHT = 900;

fn initState(allocator: std.mem.Allocator, ecs: *game.Ecs) !game.Ecs.State {
    _ = ecs;
    var physics_world = zbt.initWorld();

    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try allocator.create(zbt.DebugDrawer);
    physics_debug.* = zbt.DebugDrawer.init(allocator);
    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(.{ .draw_wireframe = true, .draw_aabb = true });

    const state = game.state.GameState{
        .window_height = WINDOW_HEIGHT,
        .window_width = WINDOW_WIDTH,
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
        .current_camera = null,
        .cameras = std.ArrayList(game.state.CameraReference).init(allocator),
    };
    return state;
}

fn createRoom(ecs: *Ecs, state: *game.state.GameState, size: f32) !struct {
    floor_shape: zbt.Shape,
} {
    const y_pos: f32 = 0.0;
    const half_size = size / 2.0;
    const floor_shape = zbt.initBoxShape(&[_]f32{ half_size, 0.1, half_size });
    var handle = try ecs.entities.register();
    std.log.warn(
        \\ Floor ID: {}
        \\
    , .{handle.identifier});

    const mesh =
        rl.genMeshPlane(size, size, 1, 1);

    var material = try rl.loadMaterialDefault();
    material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = rl.Color.dark_green;

    const transform = rl.Matrix.multiply(rl.Matrix.identity(), rl.Matrix.translate(0.0, y_pos, 0.0));
    var bundle = engine.MeshBundle.init(ecs.allocator, &[_]rl.Material{material}, transform);
    try bundle.add(mesh, 0);
    try handle.addComponent(.bundle, bundle);

    const shape = floor_shape.asShape();
    const body = engine.util.transformMassShapeToBody(transform, 0.0, shape);
    body.setRestitution(1.0);
    const body_id = state.physics.?.world.getNumBodies();
    state.physics.?.world.addBody(body);
    try handle.addComponent(.body, body_id);

    return .{
        .floor_shape = floor_shape.asShape(),
    };
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        arena.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("FAIL");
    }
    std.log.warn("INITIALIZED ALLOCATOR\n", .{});

    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // ECS Setup
    var ecs = game.Ecs.init(&arena);
    defer ecs.deinit();
    // _ = try ecs.systems.register(game.systems.CameraTrackingSystem);
    _ = try ecs.systems.register(game.systems.SyncPhysicsSystem);

    // World Setup
    //---
    zbt.init(arena.allocator());
    defer zbt.deinit();
    var state = try initState(arena.allocator(), &ecs);
    defer state.deinit();

    // const room_shapes = try createRoom(&ecs, &state, 500.0);
    // defer {
    //     room_shapes.floor_shape.deinit();
    // }

    {
        const size = 500.0;
        const y_pos: f32 = 0.0;
        const half_size = size / 2.0;
        const floor_shape = zbt.initBoxShape(&[_]f32{ half_size, 0.1, half_size });
        var handle = try ecs.entities.register();
        std.log.warn(
            \\ Floor ID: {}
            \\
        , .{handle.identifier});

        const mesh =
            rl.genMeshPlane(size, size, 1, 1);

        var material = try rl.loadMaterialDefault();
        material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = rl.Color.dark_green;

        const transform = rl.Matrix.multiply(rl.Matrix.identity(), rl.Matrix.translate(0.0, y_pos, 0.0));
        var bundle = engine.MeshBundle.init(ecs.allocator, &[_]rl.Material{material}, transform);
        try bundle.add(mesh, 0);
        try handle.addComponent(.bundle, bundle);

        const shape = floor_shape.asShape();
        const body = engine.util.transformMassShapeToBody(transform, 0.0, shape);
        body.setRestitution(1.0);
        const body_id = state.physics.?.world.getNumBodies();
        state.physics.?.world.addBody(body);
        try handle.addComponent(.body, body_id);
    }

    // I believe this shape needs to be *half* the size of the mesh??
    const d6_size = 1.0;
    const d6shape = zbt.initBoxShape(&[_]f32{
        d6_size / 2.0,
        d6_size / 2.0,
        d6_size / 2.0,
    });
    defer d6shape.deinit();

    var d6_entity_idx: usize = undefined;
    var d6_entity_id: u32 = undefined;

    // D6 ENTITY
    // ---
    {
        var handle = try ecs.entities.register();

        d6_entity_idx = handle.index() orelse @panic("NO INDEX??");
        d6_entity_id = handle.identifier;
        var inner_material = try rl.loadMaterialDefault();
        const shader = try rl.loadShader("resources/shaders/basic.vs", "resources/shaders/basic.fs");
        if (shader.id == 0) {
            @panic("SHADER FAILED TO LOAD");
        }
        inner_material.shader = shader;

        var face_material = try rl.loadMaterialDefault();
        const numbers_atlas_texture = rl.loadTexture("resources/numbers.png") catch @panic("COULD NOT GET TEXTURE FROM ATLAS IMAGE");
        face_material.maps[0].texture = numbers_atlas_texture;

        const transform = rl.Matrix.multiply(rl.Matrix.identity(), rl.Matrix.translate(0.0, 2.0, 0.0));
        var bundle = engine.MeshBundle.init(ecs.allocator, &[_]rl.Material{ inner_material, face_material }, transform);

        const inner_mesh = rl.genMeshCube(d6_size, d6_size, d6_size);
        const faces = try game.dice.genD6Faces(ecs.allocator, d6_size * 1.01);

        try bundle.add(inner_mesh, 0);
        for (faces) |mesh| {
            try bundle.add(mesh, 1);
        }

        try handle.addComponent(.bundle, bundle);

        const shape = d6shape.asShape();
        const mass: f32 = 2.0;
        var inertia: [3]f32 = .{ 0, 0, 0 };
        shape.calculateLocalInertia(mass, &inertia);
        const body = engine.util.transformMassShapeToBody(transform, mass, shape);
        body.setFriction(5.0);
        body.setSpinningFriction(5.0);
        body.setDeactivationTime(2.0);
        // Higher value = more bounce
        body.setRestitution(0.5);

        // Helps to stop spinning
        const angular_damp = 0.5;
        // Helps to stop skidding
        const linear_damp = 0.2;
        body.setDamping(linear_damp, angular_damp);
        body.setMassProps(mass, &inertia);

        const body_id = state.physics.?.world.getNumBodies();
        state.physics.?.world.addBody(body);
        try handle.addComponent(.body, body_id);
    }

    const d6track_system = game.cameras.trackingCameraSystem(arena.allocator(), d6_entity_id);
    const track_sys_id, _ = try ecs.systems.register(d6track_system);

    const camera =
        rl.Camera{
            .position = rl.Vector3.init(10.0, 10.0, 0.0),
            .target = rl.Vector3.zero(),
            .up = rl.Vector3.init(0.0, 1.0, 0.0),
            .fovy = 45.0,
            .projection = rl.CameraProjection.perspective,
        };

    var handle = try ecs.entities.register();
    try handle.addComponent(.camera, camera);
    try state.cameras.append(game.state.CameraReference{ .camera_id = handle.identifier, .system_id = track_sys_id });
    state.current_camera = 0;
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        // _ = dt;
        _ = state.physics.?.world.stepSimulation(dt, .{});
        try ecs.runSystems(&state);
        try state.update(&ecs);

        // Draw
        //---
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        try state.draw(&ecs);

        rl.drawFPS(10, 10);
    }
}

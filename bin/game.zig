const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const engine = @import("engine_core");
const game = @import("game_core");
const zm = @import("zmath");
const Vector3 = rl.Vector3;
const Ecs = game.Ecs;

const WINDOW_WIDTH = 1600;
const WINDOW_HEIGHT = 900;

fn initScene(allocator: std.mem.Allocator) !game.Ecs.Scene {
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
    };

    var scene = Ecs.Scene.init(state);
    scene.addCamera(game.cameras.BundleTrackingCamera);
    return scene;
}

/// Not **everything** has to be done in systems
/// I have opted to use procedures for drawing logic
/// This is because I would have to add complexity to systems to allow some to run during drawing
/// instead, I have opted to keep systems in *just* the update loop
fn draw(myecs: *Ecs, state: *game.state.GameState) void {
    // myecs.entities.queryEntities(myecs.allocator, )
    rl.beginMode3D(state.camera);
    defer rl.endMode3D();

    const bundle_sig = s: {
        var s = Ecs.Signature.initEmpty();
        s.set(@intFromEnum(Ecs.ComponentsTag.bundle));
        break :s s;
    };

    if (state.object_impulse) |impulse| {
        rl.drawCube(impulse.position, 0.1, 0.1, 0.1, rl.Color.ray_white);
        rl.drawLine3D(impulse.position, impulse.target, rl.Color.red);
    }

    for (0.., myecs.entities.manager.signatures) |i, sig| {
        if (sig.supersetOf(bundle_sig)) {
            const identifier = myecs.entities.manager.identifier_map.get(i) orelse break;

            std.log.warn(
                \\ Drawing Entity {}
                \\
            , .{identifier});
            const idx = myecs.entities.manager.index_map.get(identifier) orelse std.debug.panic("Entity: {} Has no index?\n", .{identifier});
            const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx).?;
            bundle.draw();
        }
    }

    rl.drawGrid(200, 5.0);

    {
        const lines = state.physics.?.debug.lines.items;
        // const num_vertices = lines.len;
        var i: usize = 0;
        while (i + 1 < lines.len) : (i += 2) {
            const start = rl.Vector3{
                .x = lines[i].position[0],
                .y = lines[i].position[1],
                .z = lines[i].position[2],
            };
            const end = rl.Vector3{
                .x = lines[i + 1].position[0],
                .y = lines[i + 1].position[1],
                .z = lines[i + 1].position[2],
            };
            // const color = lines[i].color;
            rl.drawLine3D(start, end, rl.Color.ray_white);
        }
    }
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
    var ecs = Ecs.init(&arena);
    defer ecs.deinit();
    // _ = try ecs.systems.register(game.systems.CameraTrackingSystem);
    _ = try ecs.systems.register(game.systems.SyncPhysicsSystem);

    // World Setup
    //---
    zbt.init(arena.allocator());
    defer zbt.deinit();
    var scene = try initScene(arena.allocator());
    defer scene.deinit();

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
        const body_id = scene.state.physics.world.getNumBodies();
        scene.state.physics.world.addBody(body);
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

    // D6 ENTITY
    // ---
    {
        var handle = try ecs.entities.register();

        d6_entity_idx = handle.index() orelse @panic("NO INDEX??");
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

        const body_id = scene.state.physics.world.getNumBodies();
        scene.state.physics.world.addBody(body);
        try handle.addComponent(.body, body_id);
        try handle.addComponent(.camera_track, true);
    }

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        // _ = dt;
        _ = scene.state.physics.world.stepSimulation(dt, .{});
        try ecs.runSystems(&scene.state);

        // Draw
        //---
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        scene.state.physics.world.debugDrawAll();
        draw(&ecs, &scene.state);
        scene.state.physics.debug.lines.clearRetainingCapacity();

        if (scene.state.object_impulse) |_| {
            rl.drawText("Press [P] to push the object", 50, 50, 10, rl.Color.green);
        }
        if (scene.state.upward_face) |face| {
            const text = try std.fmt.allocPrintZ(arena.allocator(), "Upward face: {}", .{face});
            rl.drawText(text, 100, 100, 10, rl.Color.green);
        }
        rl.drawFPS(10, 10);
    }
}

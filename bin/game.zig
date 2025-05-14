const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const engine = @import("engine_core");
const game = @import("game_core");
const zm = @import("zmath");
const Vector3 = rl.Vector3;
const Ecs = game.Ecs;

fn init_camera() rl.Camera3D {
    const camera = rl.Camera3D{
        .position = Vector3.init(10.0, 10.0, 10.0), // Camera position
        .target = Vector3.init(0.0, 0.0, 0.0), // Camera looking at point
        .up = Vector3.init(0.0, 1.0, 0.0), // Camera up vector (rotation towards target)
        .fovy = 45.0, // Camera field-of-view Y
        .projection = rl.CameraProjection.perspective,
    };
    return camera;
}

/// Not **everything** has to be done in systems
/// I have opted to use procedures for drawing logic
/// This is because I would have to add complexity to systems to allow some run during drawing
/// instead, I have opted to keep systems in the update loop
pub fn draw(myecs: *Ecs, state: *game.state.State) void {
    rl.beginMode3D(state.camera);
    defer rl.endMode3D();

    const phys_mesh_sig = s: {
        var s = Ecs.Signature.initEmpty();
        s.set(@intFromEnum(Ecs.ComponentsEnum.mesh));
        s.set(@intFromEnum(Ecs.ComponentsEnum.transform));
        s.set(@intFromEnum(Ecs.ComponentsEnum.material));
        break :s s;
    };
    const die_sig = s: {
        var s = Ecs.Signature.initEmpty();
        s.set(@intFromEnum(Ecs.ComponentsEnum.die));
        s.set(@intFromEnum(Ecs.ComponentsEnum.transform));
        break :s s;
    };

    // std.log.warn(
    //     \\ PhysMesh Sig: {b}
    //     \\ die Sig: {b}
    // , .{ phys_mesh_sig.mask, die_sig.mask });

    for (0.., myecs.entities.manager.signatures) |i, sig| {
        // std.log.warn("SIG: {b}\n", .{sig.mask});

        if (sig.supersetOf(phys_mesh_sig) or sig.supersetOf(die_sig)) {
            // std.log.warn("IDX: {}\n", .{i});
            const identifier = myecs.entities.manager.identifier_map.get(i) orelse break;
            // std.log.warn("DRAWING: {}\n", .{identifier});
            const idx = myecs.entities.manager.index_map.get(identifier) orelse std.debug.panic("Entity: {} Has no index?\n", .{identifier});
            const transform = myecs.components.access(rl.Matrix, Ecs.ComponentsEnum.transform, idx).?;
            if (myecs.components.access(game.Die, .die, idx)) |die| {
                std.log.warn("drawing die\n", .{});
                try die.draw(transform.*);
                continue;
            }

            const mesh = myecs.components.access(rl.Mesh, Ecs.ComponentsEnum.mesh, idx).?;
            const material = myecs.components.access(rl.Material, Ecs.ComponentsEnum.material, idx).?;
            rl.drawMesh(mesh.*, material.*, transform.*);
        }
    }
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

    const screen_width = 800;
    const screen_height = 450;
    rl.initWindow(screen_width, screen_height, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // ECS Setup
    var ecs = Ecs.init(&arena);
    defer ecs.deinit();
    try ecs.systems.register(game.systems.SyncPhysicsSystem{});
    try ecs.systems.register(game.systems.PlayerInteractSystem{});

    // World Setup
    //---
    zbt.init(arena.allocator());
    defer zbt.deinit();
    var physics_world = zbt.initWorld();

    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try arena.allocator().create(zbt.DebugDrawer);
    physics_debug.* = zbt.DebugDrawer.init(arena.allocator());
    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(.{ .draw_wireframe = true, .draw_aabb = true });

    var state = game.state.State{
        .window_height = screen_height,
        .window_width = screen_width,
        .camera = init_camera(),
        // .pick = .{
        //     .p2p = zbt.allocPoint2PointConstraint(),
        // },
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
    };

    // should be in a function
    defer state.deinit();

    const boxshape = zbt.initBoxShape(&[_]f32{ 1.0, 1.0, 1.0 });
    defer boxshape.deinit();

    var cube_entity_idx: usize = undefined;

    // CUBE ENTITY
    // ---
    {
        var handle = try ecs.entities.register();
        cube_entity_idx = handle.index() orelse @panic("NO INDEX??");

        var material = try rl.loadMaterialDefault();
        const shader = try rl.loadShader("resources/shaders/basic.vs", "resources/shaders/basic.fs");
        if (shader.id == 0) {
            @panic("SHADER FAILED TO LOAD");
        }
        material.shader = shader;
        const die = try game.Die.new(material, .six, .{ 1.0, 1.0, 1.0 });
        try handle.addComponent(Ecs.ComponentsEnum.die, &die);

        var transform = rl.Matrix.identity();
        transform = transform.multiply(rl.Matrix.translate(0.0, 10.0, 0.0));
        // We use the transform with the `Die` to store *where* it is
        try handle.addComponent(Ecs.ComponentsEnum.transform, &transform);

        const shape = boxshape.asShape();
        const body = engine.util.transformMassShapeToBody(transform, 1.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);

        try handle.addComponent(.physics_interact, &true);
    }

    // FLOOR ENTITY
    // ---
    const floor_shape = zbt.initBoxShape(&[_]f32{ 10.0, 0.1, 10.0 });

    defer floor_shape.deinit();
    {
        var handle = try ecs.entities.register();

        const mesh =
            rl.genMeshPlane(10.0, 10.0, 1, 1);
        try handle.addComponent(.mesh, &mesh);

        const transform = rl.Matrix.identity();
        try handle.addComponent(.transform, &transform);

        var material = try rl.loadMaterialDefault();
        material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = rl.Color.dark_green;
        try handle.addComponent(.material, &material);

        const shape = floor_shape.asShape();
        const body = engine.util.transformMassShapeToBody(transform, 0.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);
    }

    // Variables for mouse orbit
    // should be moved to system eventually
    const mouse_sensitivity: f32 = 0.005;
    var distance: f32 = 10.0;
    var yaw: f32 = 0.0; // Horizontal angle (radians)
    var pitch: f32 = 0.5; // Vertical angle (radians, avoid -PI/2 and PI/2)

    // Variables for mouse click
    // should also be moved to system eventually

    // var ray = zbt.RayCastFlags
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        _ = state.physics.world.stepSimulation(dt, .{});
        try ecs.runSystems(&state);

        // CAMERA TRACKING THE DICE
        // dont love how this is done for now
        // ---
        // Mouse control
        const mouse_delta = rl.getMouseDelta();
        yaw += mouse_delta.x * mouse_sensitivity;
        pitch += mouse_delta.y * mouse_sensitivity;

        // Clamp pitch to avoid flipping
        const pitch_limit: f32 = std.math.pi / 2.0 - 0.01;
        if (pitch > pitch_limit) pitch = pitch_limit;
        if (pitch < -pitch_limit) pitch = -pitch_limit;

        // Zoom with mouse wheel
        distance -= rl.getMouseWheelMove() * 1.0;
        if (distance < 2.0) distance = 2.0;
        if (distance > 50.0) distance = 50.0;

        // Convert spherical to cartesian
        const cube_entity_trans = ecs.components.access(rl.Matrix, .transform, cube_entity_idx) orelse @panic("NO CUBE??");
        const target = engine.util.extractPosition(cube_entity_trans.*);
        const new_camera_pos = Vector3.init(
            //
            target.x + distance * std.math.cos(pitch) * std.math.sin(yaw),
            //
            target.y + distance * std.math.sin(pitch),
            //
            target.z + distance * std.math.cos(pitch) * std.math.cos(yaw));
        state.camera.position = new_camera_pos;
        state.camera.target = target;

        // Impulse
        // ---

        // state.pick.p2p.*
        // Draw
        //---
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        state.physics.world.debugDrawAll();
        state.physics.debug.lines.clearRetainingCapacity();
        draw(&ecs, &state);

        rl.drawFPS(10, 10);
    }
}

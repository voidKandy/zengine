const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("engine_core");
const zm = @import("zmath");

const Vector3 = rl.Vector3;

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

const Die = core.dice.Die("resources/numbers.png");
const MAX_N_ENTITIES: usize = 1024;
const MAX_N_SYSTEMS: usize = 1024;
const Ecs = core.ecs.Ecs(MAX_N_ENTITIES, MAX_N_SYSTEMS, core.state.State, &[_]core.ecs.Component{
    .{ "die", Die },
    .{ "mesh", rl.Mesh },
    .{ "material", rl.Material },
    .{ "transform", rl.Matrix },
    .{ "shape", zbt.Shape },
    // .{ "mass", f32 },
    // Body can be gotten by querying the physics engine
    // Instead of storing the rigidbody, we store the index of the body in the physics engine
    // .{ "rigidbody", zbt.Body },
    .{ "body", i32 },
});

const SyncPhysicsSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .transform, .body }, struct {
    fn sync(entities: []core.ecs.Entity, myecs: *Ecs, state: *core.state.State) void {
        std.log.warn("IN SYNC SYSTEM\n", .{});
        for (entities) |e| {
            const idx = myecs.entities.manager.index_map.get(e).?;
            const stored_transform = myecs.components.access(rl.Matrix, .transform, idx) orelse {
                std.log.warn("Entity does not have transform component\n", .{});
                continue;
            };
            const body_id = myecs.components.access(i32, .body, idx) orelse {
                std.log.warn("Entity does not have body component\n", .{});
                continue;
            };
            // std.log.warn("DRAWING: {}\n", .{e});

            const body = state.physics.world.getBody(body_id.*);

            var transform: [12]f32 = undefined;
            body.getGraphicsWorldTransform(&transform);

            stored_transform.*.m0 = transform[0];
            stored_transform.*.m4 = transform[1];
            stored_transform.*.m8 = transform[2];

            stored_transform.*.m1 = transform[3];
            stored_transform.*.m5 = transform[4];
            stored_transform.*.m9 = transform[5];

            stored_transform.*.m2 = transform[6];
            stored_transform.*.m6 = transform[7];
            stored_transform.*.m10 = transform[8];

            stored_transform.*.m12 = transform[9];
            stored_transform.*.m13 = transform[10];
            stored_transform.*.m14 = transform[11];
        }
    }
}.sync);

/// Not **everything** has to be done in systems
/// I have opted to use procedures for drawing logic
/// This is because I would have to add complexity to systems to allow some run during drawing
/// instead, I have opted to keep systems in the update loop
pub fn draw(myecs: *Ecs, state: *core.state.State) void {
    rl.beginMode3D(state.camera);
    defer rl.endMode3D();
    var all: [MAX_N_ENTITIES]core.ecs.Entity = undefined;
    @memset(&all, 0);
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

    std.log.warn(
        \\ PhysMesh Sig: {b}
        \\ die Sig: {b}
    , .{ phys_mesh_sig.mask, die_sig.mask });

    for (0.., myecs.entities.manager.signatures) |i, sig| {
        // std.log.warn("SIG: {b}\n", .{sig.mask});

        if (sig.supersetOf(phys_mesh_sig) or sig.supersetOf(die_sig)) {
            std.log.warn("IDX: {}\n", .{i});
            const identifier = myecs.entities.manager.identifier_map.get(i) orelse break;
            std.log.warn("DRAWING: {}\n", .{identifier});
            const idx = myecs.entities.manager.index_map.get(identifier) orelse std.debug.panic("Entity: {} Has no index?\n", .{identifier});
            const transform = myecs.components.access(rl.Matrix, Ecs.ComponentsEnum.transform, idx).?;
            if (myecs.components.access(Die, .die, idx)) |die| {
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

    const screenWidth = 800;
    const screenHeight = 450;
    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // ECS Setup
    var ecs = Ecs.init(&arena);
    defer ecs.deinit();
    try ecs.systems.register(SyncPhysicsSystem{});

    // World Setup
    //---
    zbt.init(arena.allocator());
    defer zbt.deinit();
    var physics_world = zbt.initWorld();

    defer {
        const num_bodies = @as(usize, @intCast(physics_world.getNumBodies()));
        for (0..num_bodies) |_| {
            const body = physics_world.getBody(0);
            physics_world.removeBody(body);
        }
        physics_world.deinit();
    }
    // defer physics_world.deinit();
    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try arena.allocator().create(zbt.DebugDrawer);
    // defer allocator.destroy(physics_debug);
    physics_debug.* = zbt.DebugDrawer.init(arena.allocator());

    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(zbt.DebugMode.user_only);

    // Camera
    //---
    var state = core.state.State{
        .window_height = screenHeight,
        .window_width = screenWidth,
        // .entities = core.state.EntityArray.init(),
        .camera = init_camera(),
        .pick = .{
            .p2p = zbt.allocPoint2PointConstraint(),
        },
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
    };

    defer state.pick.p2p.dealloc();

    const boxshape = zbt.initBoxShape(&[_]f32{ 1.0, 1.0, 1.0 });
    defer boxshape.deinit();

    // CUBE ENTITY
    // ---
    {
        var handle = try ecs.entities.register();

        var material = try rl.loadMaterialDefault();
        const shader = try rl.loadShader("resources/shaders/basic.vs", "resources/shaders/basic.fs");
        if (shader.id == 0) {
            @panic("SHADER FAILED TO LOAD");
        }
        material.shader = shader;
        const die = try Die.new(material, .six, .{ 1.0, 1.0, 1.0 });
        try handle.addComponent(Ecs.ComponentsEnum.die, &die);

        var transform = rl.Matrix.identity();
        transform = transform.multiply(rl.Matrix.translate(0.0, 10.0, 0.0));
        // We use the transform with the `Die` to store *where* it is
        try handle.addComponent(Ecs.ComponentsEnum.transform, &transform);

        const shape = boxshape.asShape();
        const body = core.util.transformMassShapeToBody(transform, 1.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);
    }

    // FLOOR ENTITY
    // ---
    const floor_shape = zbt.initBoxShape(&[_]f32{ 10.0, 0.2, 10.0 });
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
        const body = core.util.transformMassShapeToBody(transform, 0.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);
    }

    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        _ = physics_world.stepSimulation(dt, .{});
        try ecs.runSystems(&state);
        physics_world.debugDrawAll();

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        draw(&ecs, &state);

        rl.drawFPS(10, 10);
    }
}

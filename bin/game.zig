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

const MAX_N_ENTITIES: usize = 1024;
const MAX_N_SYSTEMS: usize = 1024;
const Ecs = core.entity.Ecs(MAX_N_ENTITIES, MAX_N_SYSTEMS, core.state.State, &[_]core.entity.Component{
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
fn transformMassShapeToBody(transform: rl.Matrix, mass: f32, shape: zbt.Shape) zbt.Body {
    const body = zbt.initBody(
        mass,
        &[_]f32{
            transform.m0,
            transform.m4,
            transform.m8,

            transform.m1,
            transform.m5,
            transform.m9,

            transform.m2,
            transform.m6,
            transform.m10,

            transform.m12,
            transform.m13,
            transform.m14,
        },
        shape,
    );
    return body;
}
const SyncPhysicsSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .transform, .body }, struct {
    fn sync(entities: []core.entity.Entity, myecs: *Ecs, state: *core.state.State) void {
        std.log.warn("IN SYNC SYSTEM\n", .{});
        for (entities) |e| {
            const idx = myecs.entities.manager.index_map.get(e).?;
            // const mesh = myecs.components.arrays[@intFromEnum(.mesh)].?[idx];
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
pub fn draw(myecs: *Ecs, state: *core.state.State) void {
    rl.beginMode3D(state.camera);
    defer rl.endMode3D();
    var all: [MAX_N_ENTITIES]core.entity.Entity = undefined;
    @memset(&all, 0);
    const entities = myecs.entities.manager.getBySignatureAtLeast(&all, s: {
        var s = Ecs.Signature.initEmpty();
        s.set(@intFromEnum(Ecs.ComponentsEnum.mesh));
        s.set(@intFromEnum(Ecs.ComponentsEnum.transform));
        s.set(@intFromEnum(Ecs.ComponentsEnum.material));
        break :s s;
    }) orelse {
        std.log.warn("DRAW GOT NO ENTITIES\n", .{});
        return;
    };
    for (entities) |e| {
        const idx = myecs.entities.manager.index_map.get(e) orelse std.debug.panic("Entity: {} Has no index?\n", .{e});
        const mesh = myecs.components.access(rl.Mesh, Ecs.ComponentsEnum.mesh, idx).?;
        const transform = myecs.components.access(rl.Matrix, Ecs.ComponentsEnum.transform, idx).?;
        const material = myecs.components.access(rl.Material, Ecs.ComponentsEnum.material, idx).?;
        std.log.warn("DRAWING: {}\n", .{e});
        rl.drawMesh(mesh.*, material.*, transform.*);
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
    zbt.init(allocator);
    defer zbt.deinit();
    var physics_world = zbt.initWorld();
    defer physics_world.deinit();
    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try arena.allocator().create(zbt.DebugDrawer);
    // defer allocator.destroy(physics_debug);
    physics_debug.* = zbt.DebugDrawer.init(arena.allocator());

    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(zbt.DebugMode.user_only);

    // Camera
    //---
    const camera = init_camera();
    var state = core.state.State{
        .window_height = screenHeight,
        .window_width = screenWidth,
        // .entities = core.state.EntityArray.init(),
        .camera = camera,
        .pick = .{
            .p2p = zbt.allocPoint2PointConstraint(),
        },
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
    };

    defer state.pick.p2p.dealloc();
    defer {
        for (0..@as(usize, @intCast(state.physics.world.getNumBodies()))) |i| {
            const body = state.physics.world.getBody(@as(i32, @intCast(i)));
            defer body.deinit();
            state.physics.world.removeBody(body);
        }
    }

    const boxshape = zbt.initBoxShape(&[_]f32{ 1.0, 1.0, 1.0 });
    defer boxshape.deinit();

    // CUBE ENTITY
    // ---
    {
        var handle = try ecs.entities.register();

        const mesh =
            rl.genMeshCube(1.0, 1.0, 1.0);
        try handle.addComponent(Ecs.ComponentsEnum.mesh, &mesh);

        var transform = rl.Matrix.identity();
        transform.m13 = 5.0;
        try handle.addComponent(Ecs.ComponentsEnum.transform, &transform);

        var material = try rl.loadMaterialDefault();
        material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = rl.Color.ray_white;
        // break :mat material;

        try handle.addComponent(Ecs.ComponentsEnum.material, &material);

        const shape = boxshape.asShape();
        const body = transformMassShapeToBody(transform, 1.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);
    }

    std.log.debug("FIRST ENTITY SIG: {b}\n", .{ecs.entities.manager.signatures[0].mask});

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
        const body = transformMassShapeToBody(transform, 0.0, shape);
        const body_id = state.physics.world.getNumBodies();
        state.physics.world.addBody(body);
        try handle.addComponent(.body, &body_id);
    }

    std.log.warn("{} BODIES\n", .{physics_world.getNumBodies()});
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        _ = physics_world.stepSimulation(dt, .{});
        try ecs.runSystems(&state);
        physics_world.debugDrawAll();

        // cube_ent.update(physics_world);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        draw(&ecs, &state);
        // {
        //     rl.beginMode3D(camera);
        //     defer rl.endMode3D();

        //     // try cube_ent.draw();
        //     // try floor_ent.draw();
        // }

        rl.drawFPS(10, 10);
    }
}

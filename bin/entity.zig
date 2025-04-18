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
        .projection = rl.CameraProjection.orthographic,
    };
    return camera;
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }
    std.log.warn("INITIALIZED ALLOCATOR\n", .{});

    const screenWidth = 800;
    const screenHeight = 450;
    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // World Setup
    //---
    zbt.init(allocator);
    defer zbt.deinit();
    var physics_world = zbt.initWorld();
    defer physics_world.deinit();
    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try allocator.create(zbt.DebugDrawer);
    defer allocator.destroy(physics_debug);
    physics_debug.* = zbt.DebugDrawer.init(allocator);

    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(zbt.DebugMode.user_only);

    // Camera
    //---
    const camera = init_camera();
    var state = core.state.State{
        .window_height = screenHeight,
        .window_width = screenWidth,
        .entities = core.state.EntityArray.init(),
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

    var cube_ent = cube_ent: {
        const mesh =
            rl.genMeshCube(1.0, 1.0, 1.0);
        const shape = zbt.initBoxShape(&[_]f32{ 1.0, 1.0, 1.0 });
        var transform = rl.Matrix.identity();
        transform.m13 = 5.0;
        const material: core.entity.EntityMaterial = .{ .color = rl.Color.blue };
        const mass = 1.0;
        break :cube_ent core.entity.Entity.init(state.physics.world, mesh, material, shape.asShape(), mass, transform);
    };

    var floor_ent = floor_ent: {
        const mesh =
            rl.genMeshPlane(10.0, 10.0, 1, 1);
        const shape = zbt.initBoxShape(&[_]f32{ 10.0, 0.2, 10.0 });
        const transform = rl.Matrix.identity();
        const material: core.entity.EntityMaterial = .{ .material = try rl.loadMaterialDefault() };
        const mass = 0.0;
        break :floor_ent core.entity.Entity.init(state.physics.world, mesh, material, shape.asShape(), mass, transform);
    };

    for ([_]core.entity.Entity{ floor_ent, cube_ent }) |ent| {
        try state.entities.push_resize(ent);
    }
    defer state.cleanup_physics_world_entities();

    std.log.warn("{} BODIES\n", .{physics_world.getNumBodies()});
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        state.object_picking(false);
        _ = physics_world.stepSimulation(dt, .{});
        physics_world.debugDrawAll();

        cube_ent.update(physics_world);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            try cube_ent.draw();
            try floor_ent.draw();
        }

        rl.drawFPS(10, 10);
    }
}

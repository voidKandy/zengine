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

    // // THIS IS BAD, but okay for now
    // var idx: i32 = 0;
    // const cube_body = cube_ent.physics_body();
    // defer cube_body.deinit();
    // cube_ent.id = idx;
    // idx += 1;
    // physics_world.addBody(cube_body);
    // defer physics_world.removeBody(cube_body);
    // std.log.warn("ADDED CUBE\n", .{});

    // const floor_body = floor_ent.physics_body();
    // defer floor_body.deinit();
    // floor_ent.id = idx;
    // idx += 1;
    // physics_world.addBody(floor_body);
    // defer physics_world.removeBody(floor_body);
    // std.log.warn("ADDED FLOOR\n", .{});

    // var ray = rl.Ray{
    //     .position = Vector3.zero(),
    //     .direction = Vector3.zero(),
    // }; // Picking line ray
    // var collision = rl.RayCollision{
    //     .hit = false,
    //     .distance = 0.0,
    //     .point = Vector3.zero(),
    //     .normal = Vector3.zero(),
    // };

    std.log.warn("{} BODIES\n", .{physics_world.getNumBodies()});
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        state.object_picking(false);
        _ = physics_world.stepSimulation(dt, .{});
        physics_world.debugDrawAll();

        {
            // ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
            // collision = rl.getRayCollisionBox(ray, rl.BoundingBox{
            //     .min = Vector3.init(cube_ent.transform.m4 - cube_ent.x / 2, cube_starting_pos.y - cube_size.y / 2, cube_starting_pos.z - cube_size.z / 2),
            //     .max = Vector3.init(cube_starting_pos.x + cube_size.x / 2, cube_starting_pos.y + cube_size.y / 2, cube_starting_pos.z + cube_size.z / 2),
            // });
        }

        if (rl.isMouseButtonPressed(.left)) {
            // const wts = rl.getWorldToScreen(rl.getMousePosition(), camera);
            // const stw = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
            // const ray_hit = physics_world.rayTestClosest(wts, stw, zbt.CollisionFilter.all, zbt.CollisionFilter.all, zbt.RayCastFlags{}, zbt.RayCastResult);
            // _ = ray_hit;
        }

        cube_ent.update(physics_world);

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            // const cube_color, const wire_color = if (collision.hit)
            //     [_]rl.Color{ rl.Color.green, rl.Color.red }
            // else
            //     [_]rl.Color{ rl.Color.gray, rl.Color.light_gray };

            try cube_ent.draw();
            try floor_ent.draw();
        }

        rl.drawFPS(10, 10);
    }
}

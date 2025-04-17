const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

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
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    zbt.init(allocator);
    defer zbt.deinit();
    const physics_world = zbt.initWorld();
    defer physics_world.deinit();
    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });

    const camera = init_camera();

    var floor_pos = Vector3.init(0.0, 3.0, 0.0);
    const floor_size = Vector3.init(5.0, 0.5, 5.0);
    const floor_shape = zbt.initBoxShape(&[_]f32{ 5.0, 0.5, 5.0 });
    defer floor_shape.deinit();

    var cube_starting_pos = Vector3.init(0.0, 5.0, 0.0);
    const cube_size = Vector3.init(2.0, 2.0, 2.0);
    const physics_box_shape = zbt.initBoxShape(&[_]f32{ 2.0, 2.0, 2.0 });
    defer physics_box_shape.deinit();
    // Create rigid body that will use above shape.
    const cube_initial_transform = [_]f32{
        1.0,                 0.0,                 0.0, // orientation
        0.0,                 1.0,                 0.0,
        0.0,                 0.0,                 1.0,
        cube_starting_pos.x, cube_starting_pos.y, cube_starting_pos.z,
    };
    const cube_body = zbt.initBody(
        1.0, // mass (0.0 for static objects)
        &cube_initial_transform,
        physics_box_shape.asShape(),
    );
    defer cube_body.deinit();
    physics_world.addBody(cube_body);
    defer physics_world.removeBody(cube_body);

    const floor_initial_transform = [_]f32{
        1.0, 0.0, 0.0, // orientation
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
        0.0, 0.0, 0.0,
    };
    var floor_body = zbt.initBody(0.0, &floor_initial_transform, floor_shape.asShape());
    // floor_body.setActivationState(.active);
    // floor_body.setCollisionFlags(.{
    //     .static_object = true,
    // });
    defer floor_body.deinit();
    physics_world.addBody(floor_body);
    defer physics_world.removeBody(floor_body);

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    var ray = rl.Ray{
        .position = Vector3.zero(),
        .direction = Vector3.zero(),
    }; // Picking line ray
    var collision = rl.RayCollision{
        .hit = false,
        .distance = 0.0,
        .point = Vector3.zero(),
        .normal = Vector3.zero(),
    };

    std.log.warn("{} BODIES\n", .{physics_world.getNumBodies()});
    // Main game loop
    while (!rl.windowShouldClose()) {
        // Update
        //----------------------------------------------------------------------------------
        const dt = rl.getFrameTime();
        _ = physics_world.stepSimulation(dt, .{});
        physics_world.debugDrawAll();

        {
            ray = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
            collision = rl.getRayCollisionBox(ray, rl.BoundingBox{
                .min = Vector3.init(cube_starting_pos.x - cube_size.x / 2, cube_starting_pos.y - cube_size.y / 2, cube_starting_pos.z - cube_size.z / 2),
                .max = Vector3.init(cube_starting_pos.x + cube_size.x / 2, cube_starting_pos.y + cube_size.y / 2, cube_starting_pos.z + cube_size.z / 2),
            });
        }

        if (rl.isMouseButtonPressed(.left)) {
            // const wts = rl.getWorldToScreen(rl.getMousePosition(), camera);
            // const stw = rl.getScreenToWorldRay(rl.getMousePosition(), camera);
            // const ray_hit = physics_world.rayTestClosest(wts, stw, zbt.CollisionFilter.all, zbt.CollisionFilter.all, zbt.RayCastFlags{}, zbt.RayCastResult);
            // _ = ray_hit;
        }

        {
            const cube = physics_world.getBody(0);
            var transform: [12]f32 = undefined;
            cube.getGraphicsWorldTransform(&transform);
            cube_starting_pos.x = transform[9];
            cube_starting_pos.y = transform[10];
            cube_starting_pos.z = transform[11];
        }
        {
            const floor = physics_world.getBody(1);
            var transform: [12]f32 = undefined;
            floor.getGraphicsWorldTransform(&transform);
            floor_pos.x = transform[9];
            floor_pos.y = transform[10];
            floor_pos.z = transform[11];
        }

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.ray_white);
        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            const cube_color, const wire_color = if (collision.hit)
                [_]rl.Color{ rl.Color.green, rl.Color.red }
            else
                [_]rl.Color{ rl.Color.gray, rl.Color.light_gray };
            rl.drawCube(cube_starting_pos, cube_size.x, cube_size.y, cube_size.z, cube_color);
            rl.drawCubeWires(cube_starting_pos, cube_size.x, cube_size.y, cube_size.z, wire_color);

            rl.drawCube(floor_pos, floor_size.x, floor_size.y, floor_size.z, rl.Color.black);
            rl.drawCubeWires(floor_pos, floor_size.x, floor_size.y, floor_size.z, rl.Color.red);
        }

        rl.drawFPS(10, 10);
    }
}

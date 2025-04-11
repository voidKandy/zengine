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

/// Helper function to translate raylib transforms to physics engine transforms
fn vec3_arr(vec: Vector3) *const [3]f32 {
    const arr = [_]f32{ vec.x, vec.y, vec.z };
    return &arr;
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
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    zbt.init(allocator);
    const world = zbt.initWorld();
    defer {
        zbt.deinit();
        world.deinit();
    }

    const camera = init_camera();

    var cube_pos = Vector3.init(0.0, 1.0, 0.0);
    const cube_size = Vector3.init(2.0, 2.0, 2.0);

    const physics_box_shape = zbt.initBoxShape(vec3_arr(cube_size));
    defer physics_box_shape.deinit();
    // Create rigid body that will use above shape.
    const initial_transform = [_]f32{
        1.0, 0.0, 0.0, // orientation
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
        0.0, 1.0, 0.0, // translation SAME AS `cube_pos`
    };
    const box_body = zbt.initBody(
        1.0, // mass (0.0 for static objects)
        &initial_transform,
        physics_box_shape.asShape(),
    );
    defer box_body.deinit();
    world.addBody(box_body);
    defer world.removeBody(box_body);

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        _ = world.stepSimulation(dt, .{});

        const cube_body = world.getBody(0);
        var transform: [12]f32 = undefined;
        cube_body.getGraphicsWorldTransform(&transform);
        cube_pos.x = transform[9];
        cube_pos.y = transform[10];
        cube_pos.z = transform[11];

        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.ray_white);

        rl.beginMode3D(camera);

        // if (collision.hit) {
        //     rl.drawCube(cubePosition, cubeSize.x, cubeSize.y, cubeSize.z, RED);
        //     rl.drawCubeWires(cubePosition, cubeSize.x, cubeSize.y, cubeSize.z, MAROON);

        //     rl.drawCubeWires(cubePosition, cubeSize.x + 0.2f, cubeSize.y + 0.2f, cubeSize.z + 0.2f, GREEN);
        // } else {
        rl.drawCube(cube_pos, cube_size.x, cube_size.y, cube_size.z, rl.Color.gray);
        rl.drawCubeWires(cube_pos, cube_size.x, cube_size.y, cube_size.z, rl.Color.dark_gray);
        // }

        // rl.drawRay(ray, MAROON);
        rl.drawGrid(10, 1.0);

        rl.endMode3D();

        rl.drawText("Try clicking on the box with your mouse!", 240, 10, 20, rl.Color.dark_gray);

        // if (collision.hit) rl.drawText("BOX SELECTED", (screenWidth - rl.measureText("BOX SELECTED", 30)) / 2, (int)(screenHeight * 0.1f), 30, GREEN);

        rl.drawText("Right click mouse to toggle camera controls", 10, 430, 10, rl.Color.gray);

        rl.drawFPS(10, 10);

        //
    }
}

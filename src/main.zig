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

    zbt.init(allocator);
    const world = zbt.initWorld();
    defer {
        zbt.deinit();
        world.deinit();
    }

    const camera = init_camera();

    const cube_pos = Vector3.init(0.0, 1.0, 0.0);
    const cube_size = Vector3.init(2.0, 2.0, 2.0);

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        // TODO: Update your variables here
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
    }
}

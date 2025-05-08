const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("engine_core");
const zm = @import("zmath");

const Vector3 = rl.Vector3;

fn init_camera() rl.Camera3D {
    const camera = rl.Camera{
        .position = rl.Vector3.init(0.0, 1.0, 2.0), // Camera position
        .target = rl.Vector3.init(0.0, 0.0, 0.0), // Camera looking at point
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective, // Camera up vector (rotation towards target)
    };
    return camera;
}

const Die = core.dice.Die(core.dice.DieType.six, "resources/numbers.png");

pub fn main() !void {
    const screen_width = 800;
    const screen_height = 450;

    rl.initWindow(screen_width, screen_height, "raylib [models] example - draw cube texture");
    defer rl.closeWindow();

    const camera = init_camera();
    var material = try rl.loadMaterialDefault();
    const shader = try rl.loadShader("resources/shaders/basic.vs", "resources/shaders/basic.fs");
    if (shader.id == 0) {
        @panic("SHADER FAILED TO LOAD");
    }
    material.shader = shader;

    // var rotation = rl.Vector3.zero();

    var d6 = try Die.new(material, .{ 1.0, 1.0, 1.0 });
    while (!rl.windowShouldClose()) // Detect window close button or ESC key
    {
        // rotation.x += 0.01;
        // rotation.y += 0.005;
        // rotation.z -= 0.0025;

        // d6.model.transform = rl.Matrix.multiply(d6.model.transform, rl.Matrix.rotateXYZ(rotation));

        rl.beginDrawing();
        defer rl.endDrawing();

        {
            rl.beginMode3D(camera);
            defer rl.endMode3D();

            const position = rl.Vector3.init(0.0, 0.0, -1.0);
            const mvp_loc = rl.getShaderLocation(shader, "mvp");
            var model_matrix = rl.Matrix.identity();
            model_matrix = rl.Matrix.multiply(model_matrix, rl.Matrix.translate(position.x, position.y, position.z));
            const mvp = rl.Matrix.multiply(rl.getCameraMatrix(camera), model_matrix);
            rl.setShaderValueMatrix(shader, mvp_loc, mvp);
            try d6.draw(position);
            // rl.drawModel(d6.model, position, 1.0, rl.Color.white);

            // for (&d6.quads) |*quad| {
            //     try quad.draw(Vector3.init(0, 0, 0), 1.0);
            // }

            rl.drawGrid(10, 1.0); // Draw a grid

        }
    }
}

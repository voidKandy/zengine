const std = @import("std");
const engine = @import("engine_core");
const game = @import("game_core");
const zbt = @import("zbullet");
const rl = @import("raylib");
const LineSegment = engine.util.LineSegment;
const Vector3 = rl.Vector3;
// const Polygon = game.world.Polygon;
// const Curve3D = game.world.Curve3D;

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

fn initState(allocator: std.mem.Allocator, ecs: *game.Ecs, rng: *std.Random.DefaultPrng) !game.state.GameState {
    var physics_world = zbt.initWorld();

    const default_gravity: f32 = 10.0;
    physics_world.setGravity(&.{ 0.0, -default_gravity, 0.0 });
    var physics_debug = try allocator.create(zbt.DebugDrawer);
    physics_debug.* = zbt.DebugDrawer.init(allocator);
    physics_world.debugSetDrawer(&physics_debug.getDebugDraw());
    physics_world.debugSetMode(.{ .draw_wireframe = true, .draw_aabb = true });

    const world = try game.world.World.generate(allocator, rng);

    const static_cam_system = game.Ecs.System{
        .schedule = .explicit,
        //
        .queries = &[_]game.Ecs.Query{.{ .query = .{} }},
        //
        .runFn = struct {
            fn run(results: []game.Ecs.QueryResult, myecs: *game.Ecs, st: *game.state.GameState) void {
                const camera_id = results[0].id;
                const idx = myecs.entities.manager.index_map.get(camera_id) orelse @panic("CAMERA ENTITY DOES NOT EXIST??");
                const cam = myecs.components.access(rl.Camera3D, .camera, idx) orelse @panic("CAMERA BUNDLE DOES NOT EXIST??");
                _ = cam;
                _ = st;
            }
        }.run,
    };

    const static_sys_id, _ = try ecs.systems.register(static_cam_system);

    var cameras = std.ArrayList(game.state.CameraReference).init(allocator);
    const perspective_offset =
        game.world.BOX_MAX * 2.2;

    // Camera that overlooks whole world
    {
        const camera =
            rl.Camera{
                .position = rl.Vector3.init(perspective_offset, perspective_offset, perspective_offset),
                .target = rl.Vector3.init(0.0, 0.0, 0.0),
                .up = rl.Vector3.init(0.0, 1.0, 0.0),
                .fovy = 45.0,
                .projection = rl.CameraProjection.perspective,
            };

        var handle = try ecs.entities.register();
        try handle.addComponent(.camera, camera);
        try cameras.append(game.state.CameraReference{ .camera_id = handle.identifier, .system_id = static_sys_id });
    }

    // Birds eye view camera
    {
        const camera =
            rl.Camera3D{
                .position = rl.Vector3.init(0.0, perspective_offset + 20.0, 0.0),
                .target = rl.Vector3.init(0.0, 0.0, 0.0),
                .up = rl.Vector3.init(1.0, 0.0, 0.0),
                .fovy = 45.0,
                .projection = rl.CameraProjection.perspective,
            };

        var handle = try ecs.entities.register();
        try handle.addComponent(.camera, camera);
        try cameras.append(game.state.CameraReference{ .camera_id = handle.identifier, .system_id = static_sys_id });
    }

    // Each polygon gets a camera looking at the position of that poly
    const cam_y_offset = 1.0;
    const cam_x_offset = 5.0;
    for (world.polygons) |p| {
        const position = rl.Vector3.init(p.position.x + cam_x_offset, p.position.y + cam_y_offset, p.position.z);
        const target = p.position;
        const up = rl.Vector3.init(0.0, 1.0, 0.0);

        const camera = rl.Camera3D{
            .position = position,
            .target = target,
            .up = up,
            .fovy = 45.0,
            .projection = rl.CameraProjection.perspective,
        };

        var handle = try ecs.entities.register();
        try handle.addComponent(.camera, camera);
        try cameras.append(game.state.CameraReference{ .camera_id = handle.identifier, .system_id = static_sys_id });
    }

    const state = game.state.GameState{
        .window_height = WINDOW_HEIGHT,
        .window_width = WINDOW_WIDTH,
        .current_camera = 0,
        .cameras = cameras,
        .physics = .{
            .world = physics_world,
            .debug = physics_debug,
        },
        .world = world,
    };

    return state;
}

/// Simple quadratic Bezier: B(t) = (1-t)^2 * P0 + 2*(1-t)*t*P1 + t^2*P2
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        arena.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("FAIL");
    }

    std.log.warn("INITIALIZED ALLOCATOR\n", .{});
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "3D Line with Bounding Box");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var ecs = game.Ecs.init(&arena);
    defer ecs.deinit();

    zbt.init(arena.allocator());
    defer zbt.deinit();

    var rng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    var state = try initState(arena.allocator(), &ecs, &rng);
    defer {
        if (state.world) |w|
            w.deinit(arena.allocator());
        state.deinit();
    }

    var is_heightmap = false;

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(rl.KeyboardKey.h)) {
            is_heightmap = !is_heightmap;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.r)) {
            state = try initState(arena.allocator(), &ecs, &rng);
        }

        if (rl.isKeyPressed(rl.KeyboardKey.p)) {
            if (state.current_camera) |idx| {
                if (idx + 1 >= state.cameras.items.len)
                    state.current_camera = 0
                else
                    state.current_camera = idx + 1;
            } else {
                state.current_camera = 0;
            }
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        if (is_heightmap) {
            rl.clearBackground(rl.Color.black);
            if (state.world) |w| {
                try w.renderHeightmapTexture(arena.allocator());
            }
        } else {
            rl.clearBackground(rl.Color.dark_gray);
            try state.draw(&ecs);

            rl.drawText("Press [R] to regenerate line", 10, 10, 20, rl.Color.white);
            rl.drawText("Press [P] to change camera", 10, 40, 20, rl.Color.white);
        }
    }
}

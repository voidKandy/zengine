const std = @import("std");
pub const dice = @import("dice.zig");
pub const player = @import("player.zig");
pub const systems = @import("systems.zig");
pub const state = @import("state.zig");
const engine = @import("engine_core");
const rl = @import("raylib");
const zbt = @import("zbullet");

// pub const Die = dice.xd("resources/numbers.png");

const MAX_N_ENTITIES: usize = 1024;
const MAX_N_SYSTEMS: usize = 1024;
const CAMERAS: usize = 8;

pub const MAX_MESHES_PER_ENTITY: usize = 10;

const EcsOptions = engine.ecs.EcsOptions{
    .max_entities = MAX_N_ENTITIES,
    .max_systems = MAX_N_SYSTEMS,
    .State = state.GameState,
    .components = &[_]engine.ecs.Component{
        .{ "bundle", engine.MeshBundle },
        .{ "transform", rl.Matrix },
        .{ "shape", zbt.Shape },
        // SHOULD ONLY BE ONE ENTITY
        .{ "camera_track", bool },
        // Should also only be one entity
        // .{ "impulse_point", struct { position: rl.Vector3, direction: rl.Vector3 } },
        // REMOVE THIS!!
        .{ "physics_interact", bool },
        // .{ "mass", f32 },
        // Body can be gotten by querying the physics engine
        // Instead of storing the rigidbody, we store the index of the body in the physics engine
        // .{ "rigidbody", zbt.Body },
        .{ "body", i32 },
    },
};
pub const Ecs = engine.ecs.Ecs(EcsOptions);

test {
    std.testing.refAllDecls(@This());
}

test "scene" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var ecs = Ecs.init(&arena);
    defer ecs.deinit();

    const gmstate = state.GameState{
        .window_height = 100,
        .window_width = 100,
        // .pick = .{
        //     .p2p = zbt.allocPoint2PointConstraint(),
        // },
    };

    const camera = rl.Camera{
        .position = rl.Vector3.init(0.0, 2.0, 4.0),
        .target = rl.Vector3.init(0.0, 0.0, 0.0),
        .up = rl.Vector3.init(0.0, 1.0, 0.0),
        .fovy = 45.0,
        .projection = rl.CameraProjection.perspective,
    };

    const bundle = Ecs.Scene.CameraBundle{
        .camera = camera,
        .system = Ecs.System{
            .query = Ecs.Query{},
            .runFn = struct {
                fn run(entities: []engine.ecs.Entity, myecs: *Ecs, st: *Ecs.State) void {
                    _ = entities;
                    _ = myecs;
                    _ = st;
                }
            }.run,
        },
        // ._update = struct {
        //     fn update() void {}
        // }.update,
    };
    var scene = Ecs.Scene.init(gmstate);
    scene.addCamera(bundle);

    for (scene.cameras) |b| {
        if (b == null) break;
        _ = try ecs.systems.register(b.?.system);
    }

    std.debug.print(
        \\ BUILT SCENE SUCCESSFULLY: {any}
        \\
    , .{scene});
}

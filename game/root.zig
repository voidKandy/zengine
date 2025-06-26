const std = @import("std");
pub const dice = @import("dice.zig");
pub const player = @import("player.zig");
pub const systems = @import("systems.zig");
pub const world = @import("world.zig");
pub const cameras = @import("cameras.zig");
pub const state = @import("state.zig");
const engine = @import("engine_core");
const rl = @import("raylib");
const zbt = @import("zbullet");

// pub const Die = dice.xd("resources/numbers.png");

const MAX_N_ENTITIES: usize = 1024;
const MAX_N_SYSTEMS: usize = 1024;
const CAMERAS: usize = 8;

pub const MAX_MESHES_PER_ENTITY: usize = 10;

pub const Ecs = engine.ecs.Ecs(engine.ecs.EcsOptions{
    .max_entities = MAX_N_ENTITIES,
    .max_systems = MAX_N_SYSTEMS,
    .State = state.GameState,
    .components = &[_]engine.ecs.Component{
        .{ "bundle", engine.MeshBundle },
        .{ "camera", engine.CameraBundle },
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
});

pub const DEFAULT_CAMERA = rl.Camera3D{
    .position = rl.Vector3.init(10.0, 10.0, 10.0), // Camera position
    .target = rl.Vector3.init(0.0, 0.0, 0.0), // Camera looking at point
    .up = rl.Vector3.init(0.0, 1.0, 0.0), // Camera up vector (rotation towards target)
    .fovy = 45.0, // Camera field-of-view Y
    .projection = rl.CameraProjection.perspective,
};

test {
    std.testing.refAllDecls(@This());
}

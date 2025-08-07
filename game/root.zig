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
const MAX_N_SYSTEMS: usize = 8;
const CAMERAS: usize = 8;

pub const MAX_MESHES_PER_ENTITY: usize = 10;

/// this might belong in engine module??
pub const Ecs = engine.ecs.Ecs(engine.ecs.EcsOptions{
    .max_entities = MAX_N_ENTITIES,
    .max_systems = MAX_N_SYSTEMS,
    .State = state.GameState,
    .components = &[_]engine.ecs.ComponentDecl{
        .{ "material_mesh", engine.MaterialMesh },
        .{ "impulse", struct {
            position: rl.Vector3,
            target: rl.Vector3,
        } },
        // Have the world component have a system where it can be influenced
        //  to make things happen with the terrain
        .{ "world", world.IslandCurve },
        .{ "camera3D", rl.Camera3D },
        // .{ "ui", rl.Camera3D },
        .{ "transform", rl.Matrix },
        .{ "shape", zbt.Shape },
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

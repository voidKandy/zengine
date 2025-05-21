const std = @import("std");
pub const dice = @import("dice.zig");
pub const player = @import("player.zig");
pub const systems = @import("systems.zig");
pub const state = @import("state.zig");
const engine = @import("engine_core");
const rl = @import("raylib");
const zbt = @import("zbullet");

pub const Die = dice.Die("resources/numbers.png");

const MAX_N_ENTITIES: usize = 1024;
const MAX_N_SYSTEMS: usize = 1024;

pub const MAX_MESHES_PER_ENTITY: usize = 10;

pub const Ecs = engine.ecs.Ecs(MAX_N_ENTITIES, MAX_N_SYSTEMS, state.State, &[_]engine.ecs.Component{
    // .{ "die", Die },
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
});

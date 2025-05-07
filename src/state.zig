const core = @import("root.zig");
const zm = @import("zmath");
const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

// pub const EntityArray =
//     core.da.DynamicArray(core.ecs.OldEntity, 5);
pub const State = struct {
    window_height: f32,
    window_width: f32,
    // entities: EntityArray,
    // component_entites: core.ecs.OldEntity.Storage,
    camera: rl.Camera3D,
    mouse: struct {
        cursor_pos: [2]f64 = .{ 0, 0 },
    } = .{},
    physics: struct {
        world: zbt.World,
        debug: *zbt.DebugDrawer,
    },
    pick: struct {
        body: ?zbt.Body = null,
        p2p: zbt.Point2PointConstraint,
        saved_linear_damping: f32 = 0.0,
        saved_angular_damping: f32 = 0.0,
        saved_activation_state: zbt.BodyActivationState = .active,
        distance: f32 = 0.0,
    },

    const Self = @This();

    const camera_fovy: f32 = std.math.pi / @as(f32, 3.0);

    /// Should only be called *once*
    /// Cleans up **all** bodies in world
    pub fn cleanup_physics_world_entities(self: *Self) void {
        while (self.entities.pop()) |ent| {
            defer ent.deinit();
            self.physics.world.removeBody(ent.body);
        }
    }
};

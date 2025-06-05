const core = @import("root.zig");
const engine = @import("engine_core");
const zm = @import("zmath");
const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

/// Each of the below functions are provided by the game to
/// encapsulate specific needed camera behavior.
/// To be used as the `_update` field in`core.CameraBundle`
/// ```
/// _update: *const fn (@This()) anyerror!void,
/// ```
pub fn update(*core.CameraBundle) anyerror!void {}

pub const State = struct {
    window_height: f32,
    window_width: f32,
    // entities: EntityArray,
    // component_entites: core.ecs.OldEntity.Storage,
    scene: core.Ecs.Scene,
    /// Corresponds with the `camera_track` component
    /// Will change as the player rotates around the object
    object_impulse: ?struct {
        position: rl.Vector3,
        target: rl.Vector3,
    } = null,
    /// Maybe this is *BAD*?
    upward_face: ?u32 = null,
    physics: struct {
        world: zbt.World,
        debug: *zbt.DebugDrawer,
    },
    // pick: struct {
    //     body: ?zbt.Body = null,
    //     p2p: zbt.Point2PointConstraint,
    //     saved_linear_damping: f32 = 0.0,
    //     saved_angular_damping: f32 = 0.0,
    //     saved_activation_state: zbt.BodyActivationState = .active,
    //     distance: f32 = 0.0,
    // },

    const Self = @This();

    const camera_fovy: f32 = std.math.pi / @as(f32, 3.0);

    pub fn deinit(self: @This()) void {
        // self.pick.p2p.dealloc();
        const num_bodies = @as(usize, @intCast(self.physics.world.getNumBodies()));
        for (0..num_bodies) |_| {
            const body = self.physics.world.getBody(0);
            self.physics.world.removeBody(body);
        }
        self.physics.debug.deinit();
        self.physics.world.deinit();
    }
};

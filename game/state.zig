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
// pub fn update(*core.CameraBundle) anyerror!void {}

pub const GameState = struct {
    window_height: f32,
    window_width: f32,
    /// Corresponds with the `camera_track` component
    /// Will change as the player rotates around the object
    object_impulse: ?struct {
        position: rl.Vector3,
        target: rl.Vector3,
    } = null,
    current_camera: ?engine.ecs.Entity = null,
    // cameras: std.AutoHashMap(u32, rl.Camera3D),
    /// Maybe this is *BAD*?
    upward_face: ?u32 = null,
    physics: ?struct {
        world: zbt.World,
        debug: *zbt.DebugDrawer,
    } = null,

    const Self = @This();

    const camera_fovy: f32 = std.math.pi / @as(f32, 3.0);

    // fn runCameraSystem(self: *Self, ecs: core.Ecs) !void {
    //     if (self.current_camera) |cam_sys_id| {
    //         if (ecs.systems.getData(cam_sys_id)) |system| {}
    //     }
    // }

    pub fn deinit(self: @This()) void {
        if (self.physics) |ph| {
            const num_bodies = @as(usize, @intCast(ph.world.getNumBodies()));
            for (0..num_bodies) |_| {
                const body = ph.world.getBody(0);
                ph.world.removeBody(body);
            }
            ph.debug.deinit();
            ph.world.deinit();
        }
        // self.pick.p2p.dealloc();
    }
};

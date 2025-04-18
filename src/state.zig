const core = @import("root.zig");
const zm = @import("zmath");
const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

fn loadCenterOfMassTransform(body: zbt.Body) zm.Mat {
    var transform: [12]f32 = undefined;
    body.getCenterOfMassTransform(&transform);
    return zm.loadMat43(transform[0..]);
}

fn loadInvCenterOfMassTransform(body: zbt.Body) zm.Mat {
    var transform: [12]f32 = undefined;
    body.getInvCenterOfMassTransform(&transform);
    return zm.loadMat43(transform[0..]);
}

fn loadPivotA(p2p: zbt.Point2PointConstraint) zm.Vec {
    var pivot: [3]f32 = undefined;
    p2p.getPivotA(&pivot);
    return zm.loadArr3w(pivot, 1.0);
}

fn loadPivotB(p2p: zbt.Point2PointConstraint) zm.Vec {
    var pivot: [3]f32 = undefined;
    p2p.getPivotB(&pivot);
    return zm.loadArr3w(pivot, 1.0);
}

pub const EntityArray =
    core.da.DynamicArray(core.entity.Entity, 5);
pub const State = struct {
    window_height: f32,
    window_width: f32,
    entities: EntityArray,
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

    pub fn object_picking(state: *State, want_capture_mouse: bool) void {
        const mouse_button_is_down = rl.isMouseButtonPressed(.left) and !want_capture_mouse;

        const ray_from = zm.loadArr3([_]f32{
            state.camera.position.x,
            state.camera.position.y,
            state.camera.position.z,
        });
        const ray_to = ray_to: {
            const cursor_pos = rl.getMousePosition();

            const far_plane = zm.f32x4s(10_000.0);
            const tanfov = zm.f32x4s(@tan(0.5 * camera_fovy));
            const aspect = zm.f32x4s(state.window_width / state.window_height);

            const forward = state.camera.position.subtract(state.camera.target).normalize();
            const ray_forward = zm.loadArr3([_]f32{ forward.x, forward.y, forward.z }) * far_plane;

            const hor = zm.normalize3(zm.cross3(zm.f32x4(0, 1, 0, 0), ray_forward)) *
                zm.f32x4s(2.0) * far_plane * tanfov * aspect;
            const vert = zm.normalize3(zm.cross3(hor, ray_forward)) *
                zm.f32x4s(2.0) * far_plane * tanfov;

            const ray_to_center = ray_from + ray_forward;

            const dhor = zm.f32x4s(1.0 / state.window_width) * hor;
            const dvert = zm.f32x4s(1.0 / state.window_height) * vert;

            var ray_to = ray_to_center + zm.f32x4s(-0.5) * hor + zm.f32x4s(-0.5) * vert;
            ray_to += dhor * zm.f32x4s(cursor_pos.x);
            ray_to += dvert * zm.f32x4s(cursor_pos.y);
            break :ray_to ray_to;
        };

        if (!state.pick.p2p.isCreated() and mouse_button_is_down) {
            var result: zbt.RayCastResult = undefined;
            const is_hit = state.physics.world.rayTestClosest(
                zm.arr3Ptr(&ray_from),
                zm.arr3Ptr(&ray_to),
                .{ .default = true },
                zbt.CollisionFilter.all,
                .{ .use_gjk_convex_test = true },
                &result,
            );

            if (is_hit) if (result.body) |body| if (!body.isStaticOrKinematic()) {
                state.pick.body = body;

                state.pick.saved_linear_damping = body.getLinearDamping();
                state.pick.saved_angular_damping = body.getAngularDamping();
                state.pick.saved_activation_state = body.getActivationState();

                body.setDamping(0.4, 0.4);
                body.forceActivationState(.deactivation_disabled);

                const pivot_a = zm.mul(
                    zm.loadArr3w(result.hit_point_world, 1.0),
                    loadInvCenterOfMassTransform(body),
                );
                state.pick.p2p.create1(body, zm.arr3Ptr(&pivot_a));
                state.pick.p2p.setImpulseClamp(30.0);
                state.pick.p2p.setDebugDrawSize(0.15);

                state.physics.world.addConstraint(state.pick.p2p.asConstraint(), true);

                state.pick.distance = zm.length3(zm.loadArr3(result.hit_point_world) - ray_from)[0];
            };
        } else if (state.pick.p2p.isCreated() and mouse_button_is_down) {
            const to = ray_from + zm.normalize3(ray_to) * zm.f32x4s(state.pick.distance);
            state.pick.p2p.setPivotB(zm.arr3Ptr(&to));

            const trans_a = loadCenterOfMassTransform(state.pick.p2p.getBodyA());
            const trans_b = loadCenterOfMassTransform(state.pick.p2p.getBodyB());

            const pivot_a = loadPivotA(state.pick.p2p);
            const pivot_b = loadPivotB(state.pick.p2p);

            const position_a = zm.mul(pivot_a, trans_a);
            const position_b = zm.mul(pivot_b, trans_b);

            state.physics.world.debugDrawLine2(
                zm.arr3Ptr(&position_a),
                zm.arr3Ptr(&position_b),
                &.{ 1.0, 1.0, 0.0 },
                &.{ 1.0, 0.0, 0.0 },
            );
            state.physics.world.debugDrawSphere(zm.arr3Ptr(&position_a), 0.05, &.{ 0.0, 1.0, 0.0 });
        }

        if (!mouse_button_is_down and state.pick.p2p.isCreated()) {
            state.physics.world.removeConstraint(state.pick.p2p.asConstraint());
            state.pick.p2p.destroy();
            state.pick.body.?.setDamping(state.pick.saved_linear_damping, state.pick.saved_angular_damping);
            state.pick.body.?.setActivationState(state.pick.saved_activation_state);
            state.pick.body = null;
        }
    }
};

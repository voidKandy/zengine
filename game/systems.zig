const std = @import("std");
const zm = @import("zmath");
const rl = @import("raylib");
const zbt = @import("zbullet");
const game = @import("root.zig");
const engine = @import("engine_core");
const Ecs = game.Ecs;

/// Only a **single** entity can have the *camera_track* component at any given time
/// otherwise the game will crash :)
/// Currently is failing to draw "hit point" because these systems DO NOT run at draw time
/// Instead, I need to create another entity and flag it in a similar way to the `camera_track` and then
/// *move* it. Then I can draw the impulse direction
/// This poses an important *problem* with the way `System`s are implemented:
/// I cannot reference entites with *different* signatures in a system
pub const CameraTrackingSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .camera_track, .bundle, .body }, struct {
    const mouse_sensitivity: f32 = 0.005;
    var distance: f32 = 10.0;
    var yaw: f32 = 0.0; // Horizontal angle (radians)
    var pitch: f32 = 0.5; // Vertical angle (radians, avoid -PI/2 and PI/2)

    fn orbitTransform(state: *game.state.State, transform: rl.Matrix) void {
        const mouse_delta = rl.getMouseDelta();
        yaw += mouse_delta.x * mouse_sensitivity;
        pitch += mouse_delta.y * mouse_sensitivity;

        // Clamp pitch to avoid flipping over the top
        const pitch_limit: f32 = std.math.pi / 2.0 - 0.01;
        pitch = std.math.clamp(pitch, -pitch_limit, pitch_limit);

        // Zoom with mouse wheel
        distance -= rl.getMouseWheelMove() * 1.0;
        distance = std.math.clamp(distance, 2.0, 50.0);

        // Get the target position from the object's transform
        const target = engine.util.extractPosition(transform);

        // Spherical to Cartesian conversion
        const sin_pitch = std.math.sin(pitch);
        const cos_pitch = std.math.cos(pitch);
        const sin_yaw = std.math.sin(yaw);
        const cos_yaw = std.math.cos(yaw);

        // Calculate raw camera position
        var camera_pos = rl.Vector3{
            .x = target.x + distance * cos_pitch * sin_yaw,
            .y = target.y + distance * sin_pitch,
            .z = target.z + distance * cos_pitch * cos_yaw,
        };

        // --- Prevent going *under* the object ---
        // If camera would end up lower than the target, clamp it
        if (camera_pos.y < target.y) {
            camera_pos.y = target.y;

            // Recalculate horizontal distance based on new vertical clamp
            const horizontal_distance = std.math.sqrt(distance * distance - (camera_pos.y - target.y) * (camera_pos.y - target.y));

            camera_pos.x = target.x + horizontal_distance * sin_yaw;
            camera_pos.z = target.z + horizontal_distance * cos_yaw;
        }

        state.camera.position = camera_pos;
        state.camera.target = target;
    }

    fn run(entities: []engine.ecs.Entity, myecs: *Ecs, state: *game.state.State) void {
        std.log.warn("IN TRACKING SYSTEM\n", .{});
        std.debug.assert(entities.len == 1);
        const followed_entity = entities[0];
        const idx = myecs.entities.manager.index_map.get(followed_entity).?;

        const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx) orelse @panic("NO BUNDLE??");
        const body_id = myecs.components.access(i32, .body, idx) orelse @panic("NO BODY??");
        const transform = bundle.transform;
        orbitTransform(state, transform);
        const body = state.physics.world.getBody(body_id.*);

        if (!body.isActive()) {
            const face_up = face_up: {
                const up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
                var max_dot: f32 = -1.0;
                var best_idx: usize = 0;
                for (bundle.meshes.items[1..], 1..) |mesh, i| {
                    const normal = rl.Vector3{
                        .x = mesh.normals[0],
                        .y = mesh.normals[1],
                        .z = mesh.normals[2],
                    };

                    std.log.warn(
                        \\ Checking mesh: {}
                        \\ Got Normals: {any}
                        \\
                    , .{ i, mesh.normals.* });

                    const dot = normal.dotProduct(up);

                    if (dot > max_dot) {
                        max_dot = dot;
                        best_idx = i;
                    }
                }

                break :face_up best_idx;
            };

            state.upward_face = game.dice.DieType.six.faceIdxToValue(face_up);
            const direction = rl.Vector3.normalize(rl.Vector3.subtract(state.camera.target, state.camera.position));
            const ray_from = [3]f32{
                state.camera.position.x,
                state.camera.position.y,
                state.camera.position.z,
            };
            const ray_to = arr: {
                const vec = rl.Vector3.add(state.camera.position, rl.Vector3.scale(direction, 10_000.0));
                break :arr [3]f32{
                    vec.x,
                    vec.y,
                    vec.z,
                };
            };
            var result: zbt.RayCastResult = undefined;

            const is_hit = state.physics.world.rayTestClosest(
                &ray_from,
                &ray_to,
                .{ .default = true },
                zbt.CollisionFilter.all,
                .{
                    // .trimesh_skip_backfaces = true,
                    .use_gjk_convex_test = true,
                },
                &result,
            );

            if (is_hit) {
                const hit_point = rl.Vector3.init(
                    result.hit_point_world[0],
                    result.hit_point_world[1],
                    result.hit_point_world[2],
                );

                const flipped_hit_point = rl.Vector3.init(hit_point.x, // keep X
                    2.0 * transform.m13 - hit_point.y, // flip Y
                    hit_point.z // keep Z
                );

                const flipped_target = rl.Vector3.init(
                    ray_to[0],
                    2.0 * transform.m13 - ray_to[1],
                    ray_to[2],
                );

                const dir = rl.Vector3.normalize(rl.Vector3.subtract(flipped_target, flipped_hit_point));
                state.object_impulse = .{
                    .position = flipped_hit_point,
                    .target = rl.Vector3.add(flipped_hit_point, rl.Vector3.scale(dir, 100.0)),
                };
            }
        }

        if (rl.isKeyPressed(.p)) {
            if (state.object_impulse) |impulse| {
                const impulse_dir = rl.Vector3.normalize(rl.Vector3.subtract(impulse.target, impulse.position));

                const force_magnitude: f32 = 100.0;
                const imp = [3]f32{
                    impulse_dir.x * force_magnitude,
                    impulse_dir.y * force_magnitude,
                    impulse_dir.z * force_magnitude,
                };

                const cross_prod = impulse_dir.crossProduct(impulse.position);
                const torque_power: f32 = 50.0;

                const torque = [3]f32{
                    cross_prod.x * torque_power,
                    cross_prod.y * torque_power,
                    cross_prod.z * torque_power,
                };

                if (!body.isActive()) {
                    body.setActivationState(.active);
                }
                body.applyCentralImpulse(&imp);
                body.applyBodyTorque(&torque);
                state.object_impulse = null;
            }
        }
    }
}.run);

pub const SyncPhysicsSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .bundle, .body }, struct {
    fn run(entities: []engine.ecs.Entity, myecs: *Ecs, state: *game.state.State) void {
        std.log.warn("IN SYNC SYSTEM\n", .{});
        for (entities) |e| {
            const idx = myecs.entities.manager.index_map.get(e).?;
            const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx) orelse {
                std.log.warn(
                    \\ Entity does not have bundle???
                    \\
                , .{});
                continue;
            };
            const body_id = myecs.components.access(i32, .body, idx) orelse {
                std.log.warn(
                    \\ Entity does not have body??
                    \\
                , .{});
                continue;
            };

            const body = state.physics.world.getBody(body_id.*);

            const transform = object_to_world: {
                var transform: [12]f32 = undefined;
                body.getGraphicsWorldTransform(&transform);
                break :object_to_world zm.loadMat43(transform[0..]);
            };
            for (transform, 0..) |row, i| {
                switch (i) {
                    0 => {
                        bundle.*.transform.m0 = row[0];
                        bundle.*.transform.m1 = row[1];
                        bundle.*.transform.m2 = row[2];
                        bundle.*.transform.m3 = row[3];
                    },
                    1 => {
                        bundle.*.transform.m4 = row[0];
                        bundle.*.transform.m5 = row[1];
                        bundle.*.transform.m6 = row[2];
                        bundle.*.transform.m7 = row[3];
                    },
                    2 => {
                        bundle.*.transform.m8 = row[0];
                        bundle.*.transform.m9 = row[1];
                        bundle.*.transform.m10 = row[2];
                        bundle.*.transform.m11 = row[3];
                    },
                    3 => {
                        bundle.*.transform.m12 = row[0];
                        bundle.*.transform.m13 = row[1];
                        bundle.*.transform.m14 = row[2];
                        bundle.*.transform.m15 = row[3];
                    },
                    else => @panic("SHOULD ONLY HAVE 4 ROWS"),
                }
            }
        }
    }
}.run);

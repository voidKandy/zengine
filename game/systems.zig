const std = @import("std");
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
pub const CameraTrackingSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .camera_track, .transform, .body }, struct {
    const mouse_sensitivity: f32 = 0.005;
    var distance: f32 = 10.0;
    var yaw: f32 = 0.0; // Horizontal angle (radians)
    var pitch: f32 = 0.5; // Vertical angle (radians, avoid -PI/2 and PI/2)

    fn orbitTransform(state: *game.state.State, transform: rl.Matrix) void {

        // Mouse control
        const mouse_delta = rl.getMouseDelta();
        yaw += mouse_delta.x * mouse_sensitivity;
        pitch += mouse_delta.y * mouse_sensitivity;

        // Clamp pitch to avoid flipping
        const pitch_limit: f32 = std.math.pi / 2.0 - 0.01;
        if (pitch > pitch_limit) pitch = pitch_limit;
        if (pitch < -pitch_limit) pitch = -pitch_limit;

        // Zoom with mouse wheel
        distance -= rl.getMouseWheelMove() * 1.0;
        if (distance < 2.0) distance = 2.0;
        if (distance > 50.0) distance = 50.0;

        // Convert spherical to cartesian
        const target = engine.util.extractPosition(transform);
        const new_camera_pos = rl.Vector3.init(
            //
            target.x + distance * std.math.cos(pitch) * std.math.sin(yaw),
            //
            target.y + distance * std.math.sin(pitch),
            //
            target.z + distance * std.math.cos(pitch) * std.math.cos(yaw));
        state.camera.position = new_camera_pos;
        state.camera.target = target;
    }

    fn run(entities: []engine.ecs.Entity, myecs: *Ecs, state: *game.state.State) void {
        std.log.warn("IN TRACKING SYSTEM\n", .{});
        std.debug.assert(entities.len == 1);
        const followed_entity = entities[0];
        const idx = myecs.entities.manager.index_map.get(followed_entity).?;
        const transform = myecs.components.access(rl.Matrix, .transform, idx) orelse @panic("NO TRANSFORM??");
        const body = myecs.components.access(rl.Matrix, .body, idx) orelse @panic("NO BODY??");
        _ = body;
        orbitTransform(state, transform.*);

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
            .{ .use_gjk_convex_test = true },
            &result,
        );

        // const hitpoint_offset = rl.Vector3.init(-, y: f32, z: f32)

        if (is_hit) {
            const hit_point = rl.Vector3.init(
                result.hit_point_world[0],
                result.hit_point_world[1],
                result.hit_point_world[2],
            );

            state.object_impulse = .{
                .position = hit_point,
                .target = rl.Vector3.add(hit_point, rl.Vector3.scale(direction, 100.0)),
            };
        }
    }
}.run);

pub const SyncPhysicsSystem = Ecs.System(&[_]Ecs.ComponentsEnum{ .transform, .body }, struct {
    fn run(entities: []engine.ecs.Entity, myecs: *Ecs, state: *game.state.State) void {
        std.log.warn("IN SYNC SYSTEM\n", .{});
        for (entities) |e| {
            const idx = myecs.entities.manager.index_map.get(e).?;
            const stored_transform = myecs.components.access(rl.Matrix, .transform, idx) orelse {
                std.log.warn("Entity does not have transform component\n", .{});
                continue;
            };
            const body_id = myecs.components.access(i32, .body, idx) orelse {
                std.log.warn("Entity does not have body component\n", .{});
                continue;
            };
            // std.log.warn("DRAWING: {}\n", .{e});

            const body = state.physics.world.getBody(body_id.*);

            var transform: [12]f32 = undefined;
            body.getGraphicsWorldTransform(&transform);

            stored_transform.*.m0 = transform[0];
            stored_transform.*.m4 = transform[1];
            stored_transform.*.m8 = transform[2];

            stored_transform.*.m1 = transform[3];
            stored_transform.*.m5 = transform[4];
            stored_transform.*.m9 = transform[5];

            stored_transform.*.m2 = transform[6];
            stored_transform.*.m6 = transform[7];
            stored_transform.*.m10 = transform[8];

            stored_transform.*.m12 = transform[9];
            stored_transform.*.m13 = transform[10];
            stored_transform.*.m14 = transform[11];
        }
    }
}.run);

pub const PlayerInteractSystem = Ecs.System(&[_]Ecs.ComponentsEnum{.physics_interact}, struct {
    fn run(entities: []engine.ecs.Entity, myecs: *Ecs, state: *game.state.State) void {
        std.log.warn("IN PLAYER SYSTEM\n", .{});
        for (entities) |e| {
            const idx = myecs.entities.manager.index_map.get(e).?;

            const interact = myecs.components.access(bool, .physics_interact, idx) orelse continue;
            // const mesh = myecs.components.access(rl.Mesh, .mesh, idx).?;
            // _ = mesh;

            if (interact.* and rl.isMouseButtonPressed(rl.MouseButton.left)) {
                const ray = rl.getScreenToWorldRay(rl.getMousePosition(), state.camera);

                const ray_from = [3]f32{
                    ray.position.x,
                    ray.position.y,
                    ray.position.z,
                };

                // const ray_to = [3]f32{
                //     ray.position.x + ray.direction.x * 1000.0,
                //     ray.position.y + ray.direction.y * 1000.0,
                //     ray.position.z + ray.direction.z * 1000.0,
                // };
                const ray_to = [3]f32{
                    // ray.position.x + ray.direction.x * 1000.0,
                    // ray.position.y + ray.direction.y * 1000.0,
                    // ray.position.z + ray.direction.z * 1000.0,
                };

                var result: zbt.RayCastResult = undefined;
                const is_hit = state.physics.world.rayTestClosest(
                    // zm.arr3Ptr(&mousepos),
                    &ray_from,
                    &ray_to,
                    .{ .default = true },
                    zbt.CollisionFilter.all,
                    .{ .use_gjk_convex_test = true },
                    &result,
                );

                if (is_hit) if (result.body) |b| {
                    std.log.warn(
                        \\ HIT!!!
                    , .{});
                    const impulse_strength: f32 = 20.0;

                    const impulse = [3]f32{
                        ray.direction.x * impulse_strength,
                        ray.direction.y * impulse_strength,
                        ray.direction.z * impulse_strength,
                    };
                    b.applyCentralImpulse(&impulse);
                };
            }
        }
    }
}.run);

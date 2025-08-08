const std = @import("std");
const zm = @import("zmath");
const rl = @import("raylib");
const zbt = @import("zbullet");
const game = @import("root.zig");
const engine = @import("engine_core");
const Ecs = game.Ecs;

pub const DrawSystem = struct {
    const matmesh_query =
        Ecs.Query{
            .query = .{ .is = Ecs.QueryStatement{
                .rule = .at_least,
                .sig = Ecs.componentSignature(.material_mesh),
            } },
        };
    const image_query =
        Ecs.Query{
            .query = .{ .is = Ecs.QueryStatement{
                .rule = .at_least,
                .sig = Ecs.componentSignature(.image),
            } },
        };

    /// Currently NO draw order, this should likely be implemented down the line as things are simplyh drawn as they are accessd
    /// which is basically random
    /// `ImageBundles` are *always* drawn *before* anything 3D as of right now
    /// FOR NOW:
    /// `rl.endDrawing()` **MUST** be called after running systems
    pub fn run(_: *@This(), myecs: *Ecs, state: *Ecs.State) anyerror!void {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);

        render2D: {
            if (try myecs.queryEntities(image_query)) |*entities| {
                for (entities.query) |*ent| {
                    const img = try ent.accessComponent(engine.ImageBundle, .image);
                    try img.draw();
                }
            }
            break :render2D;
        }

        render3D: {
            const cam_ref = state.currentCamera() orelse @panic("NO CURRENT CAMERA!!");
            const camera3D: *rl.Camera3D = cam: {
                var handle = myecs.entityHandle(cam_ref.id);
                break :cam handle.accessComponent(rl.Camera3D, .camera3D) catch @panic("NO CAMERA BUNDLE?");
            };
            rl.beginMode3D(camera3D.*);
            defer rl.endMode3D();

            if (try myecs.queryEntities(matmesh_query)) |*entities| {
                for (entities.query) |*ent| {
                    const mat_mesh = try ent.accessComponent(engine.MaterialMesh, .material_mesh);
                    mat_mesh.draw();
                }
            }
            // draw a grid just cuz
            rl.drawGrid(200, 5.0);

            // draw physics debug lines
            if (state.physics) |phys| {
                const lines = phys.debug.lines.items;
                var i: usize = 0;
                while (i + 1 < lines.len) : (i += 2) {
                    const start = rl.Vector3{
                        .x = lines[i].position[0],
                        .y = lines[i].position[1],
                        .z = lines[i].position[2],
                    };
                    const end = rl.Vector3{
                        .x = lines[i + 1].position[0],
                        .y = lines[i + 1].position[1],
                        .z = lines[i + 1].position[2],
                    };
                    // const color = lines[i].color;
                    rl.drawLine3D(start, end, rl.Color.ray_white);
                }
            }
            break :render3D;
        }
    }
};

const RenderNoiseSystem = struct {
    changed: bool = false,
    noise: engine.noise.Noise,
    mesh: engine.Entity,
    texture: engine.Entity,
    /// Static for now, maybe should be a field?
    /// Idk it feels like this is the wrong place to do this?
    const MASK = &[_]rl.Vector2{
        .{ .x = 0.5, .y = 0.5 },
        .{ .x = -0.5, .y = 0.5 },
        // .{ .x = -0.7, .y = 0.0 },
        .{ .x = -0.5, .y = -0.5 },
        .{ .x = 0.5, .y = -0.5 },
        .{ .x = 0.5, .y = 0.5 },
    };

    const MESH_SIZE =
        rl.Vector3.init(16.0, 8.0, 16.0);

    pub fn start(self: *@This(), ecs: *Ecs, _: *game.state.GameState) anyerror!void {
        const image = try self.noise.createNoiseImage();
        const mesh = try engine.terrain.genMaskedImageMesh(ecs.allocator, image, MESH_SIZE, MASK, 2);
        var material = try rl.loadMaterialDefault();
        // material.maps[0].color = rl.Color.ray_white;
        const texture = try rl.loadTextureFromImage(image);
        material.maps[0].texture = texture;
        // defer rl.unloadTexture(texture);

        var mat_mesh_position = rl.Matrix.identity();
        mat_mesh_position.m12 = -8.0;
        mat_mesh_position.m14 = -8.0;
        var mat_mesh =
            engine.MaterialMesh.init(ecs.allocator, mat_mesh_position);
        const idx = try mat_mesh.add_material(material);
        try mat_mesh.add_mesh(mesh, idx);
        var entity = try ecs.entities.register();

        try entity.addComponent(.material_mesh, mat_mesh);
        try entity.addComponent(.image, image);
    }

    pub fn run(self: *@This(), results: []Ecs.QueryResult, myecs: *Ecs, state: *game.state.GameState) void {
        const mesh: *rl.Mesh = m: {
            const ent = myecs.entityHandle(self.mesh);
            break :m try ent.accessComponent(engine.MaterialMesh, .material_mesh);
        };
        const texture: *rl.RenderTexture2D = m: {
            const ent = myecs.entityHandle(self.texture);
            break :m try ent.accessComponent(rl.RenderTexture2D, .image);
        };

        if (rl.isKeyPressed(rl.KeyboardKey.r) or self.changed) {
            self.noise.drawPerlinNoiseToImage(texture);
            mesh.* = try engine.terrain.genMaskedImageMesh(self.allocator, texture, MASK, 2);
        }

        _ = results;
        _ = state;
    }
};
// bad name for this.
// This interracts with the object_impulse field of state to facilitate
// 1. forcing the camera to follow an entity
// 2. allowing the user to apply impulses on that object
// This is essentially the movement system
pub fn CameraTrackingSystem(camera_id: engine.ecs.Entity) Ecs.System {
    Ecs.System{
        .queries = &[_]Ecs.Query{
            Ecs.Query{ .id = camera_id },
            Ecs.Query{
                .query = .{ .is = Ecs.QueryStatement.new(.at_least, &[_]Ecs.ComponentsTag{ .camera_track, .bundle, .body }) },
            },
        },
        .runFn = struct {
            const mouse_sensitivity: f32 = 0.005;
            var distance: f32 = 10.0;
            var yaw: f32 = 0.0; // Horizontal angle (radians)
            var pitch: f32 = 0.5; // Vertical angle (radians, avoid -PI/2 and PI/2)

            fn orbitTransformation(state: *game.state.GameState, transform: rl.Matrix) void {
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

                const camera = state.scene.currentCamera().?.camera;
                camera.position = camera_pos;
                camera.target = target;
            }

            fn run(results: []game.Ecs.QueryResult, myecs: *Ecs, state: *game.state.GameState) void {
                std.log.warn("IN TRACKING SYSTEM\n", .{});
                const camera_entity = results[0];
                const cam_idx = myecs.entities.manager.index_map.get(camera_entity).?;
                const camera = myecs.components.access(rl.Camera3D, .camera, cam_idx) orelse @panic("NO CAMERA??");

                const followed_entity = results[1];
                // const camera = state.scene.currentCamera().?.camera;
                const idx = myecs.entities.manager.index_map.get(followed_entity).?;

                const bundle = myecs.components.access(engine.MaterialMesh, .bundle, idx) orelse @panic("NO BUNDLE??");
                const body_id = myecs.components.access(i32, .body, idx) orelse @panic("NO BODY??");
                const transform = bundle.transform;
                orbitTransformation(state, transform);
                const body = state.physics.?.world.getBody(body_id.*);

                if (!body.isActive()) {
                    const face_up = face_up: {
                        const up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
                        var max_dot: f32 = -1.0;
                        var best_idx: usize = 0;
                        var world_axis, const world_angle = engine.util.extractAxisAngle(transform);
                        world_axis = world_axis.normalize();
                        const cos_theta = @cos(world_angle);
                        const sin_theta = @sin(world_angle);
                        // Normals are in *model space*, which just means that they are not transformed based on the transform of the mesh.
                        // So, we need to change the normals based on the rotation of the mesh
                        for (bundle.meshes.items[1..], 1..) |mesh, i| {
                            const adjusted_normal = blk: {
                                const normal = rl.Vector3{
                                    .x = mesh.normals[0],
                                    .y = mesh.normals[1],
                                    .z = mesh.normals[2],
                                };

                                const cross = rl.Vector3{
                                    .x = world_axis.y * normal.z - world_axis.z * normal.y,
                                    .y = world_axis.z * normal.x - world_axis.x * normal.z,
                                    .z = world_axis.x * normal.y - world_axis.y * normal.x,
                                };

                                const dot = world_axis.dotProduct(normal);

                                const adjusted =
                                    rl.Vector3{
                                        .x = normal.x * cos_theta + cross.x * sin_theta + world_axis.x * dot * (1.0 - cos_theta),
                                        .y = normal.y * cos_theta + cross.y * sin_theta + world_axis.y * dot * (1.0 - cos_theta),
                                        .z = normal.z * cos_theta + cross.z * sin_theta + world_axis.z * dot * (1.0 - cos_theta),
                                    };

                                break :blk adjusted.normalize();
                            };

                            std.log.warn(
                                \\ Checking mesh: {}
                                \\
                            , .{
                                i,
                            });

                            std.log.warn(
                                \\ NORM:  {}
                                \\
                            , .{adjusted_normal});

                            const dot = adjusted_normal.dotProduct(up);

                            if (dot > max_dot) {
                                max_dot = dot;
                                best_idx = i;
                            }
                        }

                        break :face_up best_idx;
                    };
                    std.log.warn(
                        \\ BEST INDEX: {}
                        \\
                    , .{face_up});

                    state.upward_face = game.dice.DieType.six.faceIdxToValue(face_up - 1);
                    // state.physics.world.getGravity(gravity: *[3]f32)
                    const direction = rl.Vector3.normalize(rl.Vector3.subtract(camera.target, camera.position));
                    const ray_from = [3]f32{
                        camera.position.x,
                        camera.position.y,
                        camera.position.z,
                    };
                    const ray_to = arr: {
                        const vec = rl.Vector3.add(camera.position, rl.Vector3.scale(direction, 10_000.0));
                        break :arr [3]f32{
                            vec.x,
                            vec.y,
                            vec.z,
                        };
                    };
                    var result: zbt.RayCastResult = undefined;

                    const is_hit = state.physics.?.world.rayTestClosest(
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
        }.run,
    };
}

pub const SyncPhysicsSystem = Ecs.System{
    .schedule = .automatic,
    .queries = &[_]Ecs.Query{.{ .query = .{ .is = Ecs.QueryStatement.new(.at_least, &[_]Ecs.ComponentsTag{ .bundle, .body }) } }},
    .runFn = struct {
        fn run(results: []game.Ecs.QueryResult, myecs: *Ecs, state: *game.state.GameState) void {
            std.log.warn("IN SYNC SYSTEM\n", .{});
            for (results[0].query) |e| {
                const idx = myecs.entities.manager.index_map.get(e).?;
                const bundle = myecs.components.access(engine.MaterialMesh, .bundle, idx) orelse {
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

                const body = state.physics.?.world.getBody(body_id.*);

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
    }.run,
};

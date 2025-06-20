const std = @import("std");
const zm = @import("zmath");
const rl = @import("raylib");
const zbt = @import("zbullet");
const game = @import("root.zig");
const engine = @import("engine_core");

// Tracks an entity marked with the `camera_track` component
// ONLY ONE CAN BE MARKED WITH THIS
// POTENTIALLY BAD!!
// maybe its better if we just kept track of the entity we are following by it's ID?
// POtenentially, make functions take a `type` at runtime
// pub const BundleTrackingCamera = game.Ecs.Scene.CameraBundle{
//     .camera = game.DEFAULT_CAMERA_BUNDLE,

//     .system = .{
//         game.Ecs.Query{ .query = .{ .is = game.Ecs.QueryStatement.new(.at_least, &[_]game.Ecs.ComponentsTag{ .camera_track, .bundle, .body }) } },

//         struct {
//             const MOUSE_SENSITIVITY: f32 = 0.005;
//             var DISTANCE: f32 = 10.0;
//             var YAW: f32 = 0.0; // Horizontal angle (radians)
//             var PITCH: f32 = 0.5; // Vertical angle (radians, avoid -PI/2 and PI/2)
//             fn orbitTransformation(state: *game.state.GameState, transform: rl.Matrix) void {
//                 const mouse_delta = rl.getMouseDelta();
//                 YAW += mouse_delta.x * MOUSE_SENSITIVITY;
//                 PITCH += mouse_delta.y * MOUSE_SENSITIVITY;
//                 // Clamp pitch to avoid flipping over the top
//                 const pitch_limit: f32 = std.math.pi / 2.0 - 0.01;
//                 PITCH = std.math.clamp(PITCH, -pitch_limit, pitch_limit);
//                 // Zoom with mouse wheel
//                 DISTANCE -= rl.getMouseWheelMove() * 1.0;
//                 DISTANCE = std.math.clamp(DISTANCE, 2.0, 50.0);
//                 // Get the target position from the object's transform
//                 const target = engine.util.extractPosition(transform);
//                 // Spherical to Cartesian conversion
//                 const sin_pitch = std.math.sin(PITCH);
//                 const cos_pitch = std.math.cos(PITCH);
//                 const sin_yaw = std.math.sin(YAW);
//                 const cos_yaw = std.math.cos(YAW);
//                 // Calculate raw camera position
//                 var camera_pos = rl.Vector3{
//                     .x = target.x + DISTANCE * cos_pitch * sin_yaw,
//                     .y = target.y + DISTANCE * sin_pitch,
//                     .z = target.z + DISTANCE * cos_pitch * cos_yaw,
//                 };
//                 // --- Prevent going *under* the object ---
//                 // If camera would end up lower than the target, clamp it
//                 if (camera_pos.y < target.y) {
//                     camera_pos.y = target.y;
//                     // Recalculate horizontal distance based on new vertical clamp
//                     const horizontal_distance = std.math.sqrt(DISTANCE * DISTANCE - (camera_pos.y - target.y) * (camera_pos.y - target.y));
//                     camera_pos.x = target.x + horizontal_distance * sin_yaw;
//                     camera_pos.z = target.z + horizontal_distance * cos_yaw;
//                 }
//                 // const camera = state.scene.currentCamera().?.camera;
//                 camera.position = camera_pos;
//                 camera.target = target;
//             }
//             fn run(cam: rl.Camera3D, entities: []engine.ecs.Entity, myecs: *game.Ecs, state: *game.Ecs.State) void {
//                 std.log.warn("IN TRACKING SYSTEM\n", .{});
//                 std.debug.assert(entities.len == 1);
//                 const followed_entity = entities[0];
//                 const idx = myecs.entities.manager.index_map.get(followed_entity).?;
//                 const bundle = myecs.components.access(engine.MeshBundle, .bundle, idx) orelse @panic("NO BUNDLE??");
//                 const body_id = myecs.components.access(i32, .body, idx) orelse @panic("NO BODY??");
//                 const transform = bundle.transform;
//                 orbitTransformation(state, transform);
//                 const body = state.physics.?.world.getBody(body_id.*);
//                 if (!body.isActive()) {
//                     const face_up = face_up: {
//                         const up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
//                         var max_dot: f32 = -1.0;
//                         var best_idx: usize = 0;
//                         var world_axis, const world_angle = engine.util.extractAxisAngle(transform);
//                         world_axis = world_axis.normalize();
//                         const cos_theta = @cos(world_angle);
//                         const sin_theta = @sin(world_angle);
//                         // Normals are in *model space*, which just means that they are not transformed based on the transform of the mesh.
//                         // So, we need to change the normals based on the rotation of the mesh
//                         for (bundle.meshes.items[1..], 1..) |mesh, i| {
//                             const adjusted_normal = blk: {
//                                 const normal = rl.Vector3{
//                                     .x = mesh.normals[0],
//                                     .y = mesh.normals[1],
//                                     .z = mesh.normals[2],
//                                 };
//                                 const cross = rl.Vector3{
//                                     .x = world_axis.y * normal.z - world_axis.z * normal.y,
//                                     .y = world_axis.z * normal.x - world_axis.x * normal.z,
//                                     .z = world_axis.x * normal.y - world_axis.y * normal.x,
//                                 };
//                                 const dot = world_axis.dotProduct(normal);
//                                 const adjusted =
//                                     rl.Vector3{
//                                         .x = normal.x * cos_theta + cross.x * sin_theta + world_axis.x * dot * (1.0 - cos_theta),
//                                         .y = normal.y * cos_theta + cross.y * sin_theta + world_axis.y * dot * (1.0 - cos_theta),
//                                         .z = normal.z * cos_theta + cross.z * sin_theta + world_axis.z * dot * (1.0 - cos_theta),
//                                     };
//                                 break :blk adjusted.normalize();
//                             };
//                             std.log.warn(
//                                 \\ Checking mesh: {}
//                                 \\
//                             , .{
//                                 i,
//                             });
//                             std.log.warn(
//                                 \\ NORM:  {}
//                                 \\
//                             , .{adjusted_normal});
//                             const dot = adjusted_normal.dotProduct(up);
//                             if (dot > max_dot) {
//                                 max_dot = dot;
//                                 best_idx = i;
//                             }
//                         }
//                         break :face_up best_idx;
//                     };
//                     std.log.warn(
//                         \\ BEST INDEX: {}
//                         \\
//                     , .{face_up});
//                     state.upward_face = game.dice.DieType.six.faceIdxToValue(face_up - 1);
//                     // state.physics.world.getGravity(gravity: *[3]f32)
//                     const direction = rl.Vector3.normalize(rl.Vector3.subtract(cam.target, cam.position));
//                     const ray_from = [3]f32{
//                         cam.position.x,
//                         cam.position.y,
//                         cam.position.z,
//                     };
//                     const ray_to = arr: {
//                         const vec = rl.Vector3.add(cam.position, rl.Vector3.scale(direction, 10_000.0));
//                         break :arr [3]f32{
//                             vec.x,
//                             vec.y,
//                             vec.z,
//                         };
//                     };
//                     var result: zbt.RayCastResult = undefined;
//                     const is_hit = state.physics.?.world.rayTestClosest(
//                         &ray_from,
//                         &ray_to,
//                         .{ .default = true },
//                         zbt.CollisionFilter.all,
//                         .{
//                             // .trimesh_skip_backfaces = true,
//                             .use_gjk_convex_test = true,
//                         },
//                         &result,
//                     );
//                     if (is_hit) {
//                         const hit_point = rl.Vector3.init(
//                             result.hit_point_world[0],
//                             result.hit_point_world[1],
//                             result.hit_point_world[2],
//                         );
//                         const flipped_hit_point = rl.Vector3.init(hit_point.x, // keep X
//                             2.0 * transform.m13 - hit_point.y, // flip Y
//                             hit_point.z // keep Z
//                         );
//                         const flipped_target = rl.Vector3.init(
//                             ray_to[0],
//                             2.0 * transform.m13 - ray_to[1],
//                             ray_to[2],
//                         );
//                         const dir = rl.Vector3.normalize(rl.Vector3.subtract(flipped_target, flipped_hit_point));
//                         state.object_impulse = .{
//                             .position = flipped_hit_point,
//                             .target = rl.Vector3.add(flipped_hit_point, rl.Vector3.scale(dir, 100.0)),
//                         };
//                     }
//                 }
//                 if (rl.isKeyPressed(.p)) {
//                     if (state.object_impulse) |impulse| {
//                         const impulse_dir = rl.Vector3.normalize(rl.Vector3.subtract(impulse.target, impulse.position));
//                         const force_magnitude: f32 = 100.0;
//                         const imp = [3]f32{
//                             impulse_dir.x * force_magnitude,
//                             impulse_dir.y * force_magnitude,
//                             impulse_dir.z * force_magnitude,
//                         };
//                         const cross_prod = impulse_dir.crossProduct(impulse.position);
//                         const torque_power: f32 = 50.0;
//                         const torque = [3]f32{
//                             cross_prod.x * torque_power,
//                             cross_prod.y * torque_power,
//                             cross_prod.z * torque_power,
//                         };
//                         if (!body.isActive()) {
//                             body.setActivationState(.active);
//                         }
//                         body.applyCentralImpulse(&imp);
//                         body.applyBodyTorque(&torque);
//                         state.object_impulse = null;
//                     }
//                 }
//             }
//         }.run,
//     },
// };

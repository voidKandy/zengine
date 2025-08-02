const core = @import("root.zig");
const engine = @import("engine_core");
const zm = @import("zmath");
const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

pub const CameraReference = struct { camera_id: u32, system_id: ?u32 = null };

pub const GameState = struct {
    window_height: f32,
    window_width: f32,
    /// Corresponds with the `camera_track` component
    /// Will change as the player rotates around the object
    object_impulse: ?struct {
        position: rl.Vector3,
        target: rl.Vector3,
    } = null,
    world: ?core.world.World = null,
    /// Stores camera entity ID as well as it's associated system (if it has one)
    current_camera: ?usize,
    cameras: std.ArrayList(CameraReference),
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

    pub fn currentCamera(self: @This()) ?CameraReference {
        const idx = self.current_camera orelse return null;
        return self.cameras.items[idx];
    }
    pub fn deinit(self: @This()) void {
        defer self.cameras.deinit();
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

    pub fn update(self: *@This(), ecs: *core.Ecs) !void {
        const cam_ref = self.currentCamera() orelse @panic("NO CAMERA??");
        std.log.warn(
            \\ GOT CAM REF: {any}
            \\
        , .{cam_ref});
        if (cam_ref.system_id) |sys_id| {
            const sys = ecs.systems.getData(sys_id) orelse {
                std.log.warn(
                    \\ NO SYSTEM WITH ID: {d}
                    \\
                , .{sys_id});
                @panic("");
            };
            std.log.warn(
                \\ RUNNING CAMERA SYSTEM
            , .{});
            try ecs.runSystem(self, sys);
        }
    }
    pub fn draw(self: @This(), ecs: *core.Ecs) !void {

        // First, camera stuff
        const cam_ref = self.cameras.items[self.current_camera orelse @panic("NO CURRENT CAMERA!!")];
        const camera_bundle = cam: {
            const idx = ecs.entities.manager.index_map.get(cam_ref.camera_id) orelse @panic("NO CAMERA??");
            break :cam ecs.components.access(rl.Camera3D, .camera, idx) orelse @panic("NO CAMERA BUNDLE?");
        };

        rl.beginMode3D(camera_bundle.*);
        defer rl.endMode3D();

        // Once the camera system has been run, we query for `MaterialMesh`s
        const bundle_sig = s: {
            var s = core.Ecs.Signature.initEmpty();
            s.set(@intFromEnum(core.Ecs.ComponentsTag.bundle));
            break :s s;
        };

        if (self.world) |world| {
            std.log.warn(
                \\ Drawing world
            , .{});

            // For drawing the world boundaries in debug mode
            const box_center = rl.Vector3.init(
                (core.world.BOX_MIN + core.world.BOX_MAX) / 2.0,
                (core.world.BOX_MIN + core.world.BOX_MAX) / 2.0,
                (core.world.BOX_MIN + core.world.BOX_MAX) / 2.0,
            );
            const box_size = rl.Vector3.init(
                core.world.BOX_MAX - core.world.BOX_MIN,
                core.world.BOX_MAX - core.world.BOX_MIN,
                core.world.BOX_MAX - core.world.BOX_MIN,
            );

            world.curve.draw();
            for (world.meshes) |mesh| {
                mesh.draw();
                // mesh.@"1".draw(material: Material, )
            }
            // for (world.polygons) |p| {
            //     p.draw();
            // }
            if (world.debug_mode)
                rl.drawCubeWires(box_center, box_size.x, box_size.y, box_size.z, rl.Color.light_gray);
        }

        const bundle_query_result =
            try ecs.queryEntities(ecs.allocator, core.Ecs.Query{ .query = .{ .is = core.Ecs.QueryStatement{ .rule = .at_least, .sig = bundle_sig } } });

        if (bundle_query_result) |bundle_entities| {
            // we draw any entities with a bundle
            for (bundle_entities.query) |id| {
                const idx = ecs.entities.manager.index_map.get(id) orelse std.debug.panic("Entity: {} Has no index?\n", .{id});
                const bundle = ecs.components.access(engine.MaterialMesh, .bundle, idx).?;
                bundle.draw();
            }
        }

        // draw the impulse line
        if (self.object_impulse) |impulse| {
            rl.drawText("Press [P] to push the object", 50, 50, 10, rl.Color.green);
            rl.drawCube(impulse.position, 0.1, 0.1, 0.1, rl.Color.ray_white);
            rl.drawLine3D(impulse.position, impulse.target, rl.Color.red);
        }

        if (self.upward_face) |face| {
            const text = try std.fmt.allocPrintZ(ecs.allocator, "Upward face: {}", .{face});
            rl.drawText(text, 100, 100, 10, rl.Color.green);
        }

        // draw a grid just cuz
        rl.drawGrid(200, 5.0);

        // draw physics debug lines
        if (self.physics) |phys| {
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
    }
};

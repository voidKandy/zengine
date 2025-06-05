const std = @import("std");
pub const da = @import("dynamic_array.zig");
pub const ecs = @import("ecs.zig");
pub const util = @import("util.zig");
pub const noise = @import("noise.zig");
pub const MeshBundle = @import("MeshBundle.zig");
pub const Type = std.builtin.Type;

test {
    std.testing.refAllDecls(@This());
}

pub fn Scene(
    comptime MAX_CAMERAS: usize,
    comptime EcsOptions: ecs.EcsOptions,
) type {
    return struct {
        const ThisEcs = ecs.Ecs(EcsOptions);

        /// The `query` argument is the set of components that either have an impact on the camera
        /// or are impacted by the camera in some way
        const CameraBundle = struct {
            camera: @import("raylib").Camera3D,
            // _update: *const fn (*@This(), ThisEcs.Query) anyerror!void,

        };

        const Self = @This();

        current: usize,
        amount: usize,
        /// Should be *tightly packed*
        /// No gaps of `null` between bundles
        /// To ensure this, the `remove` method moves the last camera to the index of the removed camera bundle
        cameras: [MAX_CAMERAS]?CameraBundle,

        pub fn init() Self {
            var cameras: [MAX_CAMERAS]?CameraBundle = undefined;
            @memset(&cameras, null);
            return .{
                .current = 0,
                .amount = 0,
                .cameras = cameras,
            };
        }

        pub fn selectNext(self: *Self) void {
            const next = self.current + 1;
            if ((next >= self.cameras.len) or self.cameras[next] == null) {
                self.current = 0;
            } else {
                self.current = next;
            }
        }

        pub fn selectPrev(self: *Self) void {
            const prev = self.current - 1;
            if ((prev <= 0)) {
                self.current = blk: {
                    var count: usize = 0;
                    while (self.cameras) |_| {
                        count += 1;
                    }
                    break :blk count;
                };
            } else {
                self.current = prev;
            }
        }

        pub fn select(self: *Self, idx: usize) !void {
            if (self.cameras[idx] == null) {
                return error.NoCamera;
            }

            self.current = idx;
        }

        pub fn currentCamera(self: Self) ?CameraBundle {
            return self.cameras[self.current];
        }

        pub fn add(self: *Self, cam: CameraBundle) void {
            var idx: usize = 0;
            for (self.cameras) |c| {
                if (c == null) break;
                idx += 1;
            }
            std.debug.assert(idx < MAX_CAMERAS);
            self.cameras[idx] = cam;
            self.amount += 1;
        }

        pub fn remove(self: *Self, idx: usize) void {
            self.cameras[idx] = self.cameras[self.amount - 1];
            self.amount -= 1;
        }
    };
}

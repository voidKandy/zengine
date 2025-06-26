const std = @import("std");
const core = @import("root.zig");
const rl = @import("raylib");
const zbt = @import("zbullet");
const Self = @This();

// transform: rl.Matrix,
camera: rl.Camera3D,
active: bool = false,

// pub fn init(camera: rl.Camera3D, transform: rl.Matrix) Self {
//     return .{ .camera = camera, .transform = transform, .active = false };
// }

pub inline fn camQuery(comptime ecsopts: core.ecs.EcsOptions) core.ecs.Ecs(ecsopts).Query {
    return core.ecs.Ecs(ecsopts).Query{
        .query = .{
            .is = core.ecs.Ecs(ecsopts).QueryStatement{
                .rule = .at_least,
                .sig = core.ecs.Ecs(ecsopts).componentsSignature(&[_]core.ecs.Ecs(ecsopts).ComponentsTag{.camera}),
            },
        },
    };
}

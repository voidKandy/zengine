const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

const Entity = struct {
    mesh_id: u32,
    shape: zbt.Shape,
    transform: rl.Vector3,
    const Self = @This();
    fn new() Self {}
};

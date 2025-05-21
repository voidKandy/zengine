const std = @import("std");
pub const da = @import("dynamic_array.zig");
pub const ecs = @import("ecs.zig");
pub const cm = @import("composite_mesh.zig");
pub const util = @import("util.zig");

test {
    std.testing.refAllDecls(@This());
}

const rl = @import("raylib");
const zbt = @import("zbullet");

pub const MeshBundle = struct {
    transform: rl.Matrix,
    materials: []const rl.Material,
    meshes: std.ArrayList(rl.Mesh),
    /// Maps index of mesh to index of material
    mesh_material_map: std.AutoHashMap(usize, usize),
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, materials: []const rl.Material, transform: rl.Matrix) Self {
        const map = std.AutoHashMap(usize, usize).init(allocator);
        const meshes = std.ArrayList(rl.Mesh).init(allocator);
        return Self{
            .transform = transform,
            .meshes = meshes,
            .materials = materials,
            .mesh_material_map = map,
        };
    }

    pub fn deinit(self: *Self) void {
        self.mesh_material_map.deinit();
        self.meshes.deinit();
    }

    pub fn add(self: *Self, mesh: rl.Mesh, material_idx: usize) !void {
        if (self.materials.len < material_idx) {
            return error.InvalidMaterialIndex;
        }
        const idx =
            self.meshes.items.len;
        try self.meshes.append(mesh);
        try self.mesh_material_map.put(idx, material_idx);
    }
};

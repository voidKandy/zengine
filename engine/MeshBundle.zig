const std = @import("std");
const rl = @import("raylib");
const zbt = @import("zbullet");
const Self = @This();

transform: rl.Matrix,
materials: []const rl.Material,
meshes: std.ArrayList(rl.Mesh),
/// Maps *index of mesh* to *index of material*
mesh_material_map: std.AutoHashMap(usize, usize),

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

pub fn draw(self: Self) void {
    // In order to ensure meshes are drawn in the order they were inserted
    // we iterate through their indices
    for (0..self.meshes.items.len) |mesh_idx| {
        const mat_idx = self.mesh_material_map.get(mesh_idx) orelse @panic("MESH DOESN'T HAVE MATERIAL??");
        std.log.warn(
            \\ Rendering Mesh {}
            \\ With Material {}
            \\
        , .{ mesh_idx, mat_idx });

        const mesh = self.meshes.items[mesh_idx];
        const mat = self.materials[mat_idx];

        if (@intFromPtr(&mesh) == 0 or @intFromPtr(&mat) == 0) {
            std.log.err(
                \\ Mesh or Material is null
                \\ Mesh Idx: {}
                \\ Material Idx: {}
                \\ 
            , .{ mesh_idx, mat_idx });
            return;
        }

        mesh.draw(mat, self.transform);
    }
}

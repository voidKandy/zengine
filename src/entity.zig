const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const Shape = zbt.Shape;

fn arr_to_matrix(arr: *[12]f32) rl.Matrix {
    return rl.Matrix{
        .m0 = arr[0],
        .m4 = arr[4],
        .m8 = arr[8],
        .m12 = arr[12],
        .m1 = arr[1],
        .m5 = arr[5],
        .m9 = arr[9],
        .m13 = arr[13],
        .m2 = arr[2],
        .m6 = arr[6],
        .m10 = arr[10],
        .m14 = arr[14],
        .m3 = arr[3],
        .m7 = arr[7],
        .m11 = arr[11],
        .m15 = arr[15],
    };
}

const MaterialTag = enum { color, material };

pub const EntityMaterial = union(MaterialTag) { color: (rl.Color), material: (rl.Material) };

pub const Entity = struct {
    id: i32,
    mesh: rl.Mesh,
    material: EntityMaterial,
    body: zbt.Body,
    /// Collision shape
    shape: Shape,
    /// 0.0 For static
    mass: f32,
    /// Column-major 4x4 matrix:
    /// | m0   m4   m8   m12 |   <- X axis + translation X
    /// | m1   m5   m9   m13 |   <- Y axis + translation Y
    /// | m2   m6   m10  m14 |   <- Z axis + translation Z
    /// | m3   m7   m11  m15 |   <- perspective row (typically 0 0 0 1)
    transform: rl.Matrix,
    const Self = @This();

    pub fn init(
        world: zbt.World,
        mesh: rl.Mesh,
        material: EntityMaterial,
        shape: Shape,
        mass: f32,
        transform: rl.Matrix,
    ) Self {
        const id = world.getNumBodies();
        const body = zbt.initBody(
            mass,
            &[_]f32{
                transform.m0,
                transform.m4,
                transform.m8,

                transform.m1,
                transform.m5,
                transform.m9,

                transform.m2,
                transform.m6,
                transform.m10,

                transform.m12,
                transform.m13,
                transform.m14,
            },
            shape,
        );

        world.addBody(body);

        return Self{
            .id = id,
            .body = body,
            .mass = mass,
            .material = material,
            .shape = shape,
            .mesh = mesh,
            .transform = transform,
        };
    }

    pub fn deinit(self: Self) void {
        self.shape.deinit();
        self.body.deinit();
    }

    pub fn update(self: *Self, world: zbt.World) void {
        const body = world.getBody(self.id);
        var transform: [12]f32 = undefined;
        body.getGraphicsWorldTransform(&transform);

        self.transform.m0 = transform[0];
        self.transform.m4 = transform[1];
        self.transform.m8 = transform[2];

        self.transform.m1 = transform[3];
        self.transform.m5 = transform[4];
        self.transform.m9 = transform[5];

        self.transform.m2 = transform[6];
        self.transform.m6 = transform[7];
        self.transform.m10 = transform[8];

        self.transform.m12 = transform[9];
        self.transform.m13 = transform[10];
        self.transform.m14 = transform[11];
    }

    pub fn draw(self: *Self) anyerror!void {
        // std.log.warn("DRAWING: {any}\n", .{self.transform});
        const material: rl.Material =
            mat: switch (self.material) {
                .color => |c| {
                    var material = try rl.loadMaterialDefault();
                    material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = c;
                    break :mat material;
                },
                .material => |m| {
                    break :mat m;
                },
            };
        rl.drawMesh(self.mesh, material, self.transform);
    }
};

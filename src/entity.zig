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

pub const Entity = struct {
    // mesh_id: u32,
    mesh: rl.Mesh,
    // material: rl.Material,
    material: rl.Material,
    shape: Shape,
    mass: f32,
    /// Column-major 4x4 matrix:
    /// X ROTATION  | m0  m4  m8  m12 |
    /// Y ROTATION  | m1  m5  m9  m13 |
    /// Z ROTATION  | m2  m6  m10 m14 |
    /// TRANSLATION | m3  m7  m11 m15 |
    transform: rl.Matrix,
    const Self = @This();

    pub fn deinit(self: Self) void {
        self.shape.deinit();
    }

    pub fn physics_body(self: *Self) zbt.Body {
        return zbt.initBody(
            self.mass,
            &[_]f32{
                self.transform.m0,
                self.transform.m4,
                self.transform.m8,
                // self.transform.m12,
                self.transform.m1,
                self.transform.m5,
                self.transform.m9,
                // self.transform.m13,
                self.transform.m2,
                self.transform.m6,
                self.transform.m10,
                // self.transform.m14,
                self.transform.m3,
                self.transform.m7,
                self.transform.m11,
                    // self.transform.m15,
            },
            self.shape,
        );
    }
    // fn draw(self: Self) void {
    //     rl.drawMesh(self.mesh, self.material, matrix);
    // }
};

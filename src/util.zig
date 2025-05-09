const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");

/// Translation (x = m12, y = m13, z = m14)
/// ```
/// | m0  m4  m8   m12 |
/// | m1  m5  m9   m13 |
/// | m2  m6  m10  m14 |
/// | m3  m7  m11  m15 |
/// ```
pub fn transformPosition(transform: rl.Matrix) rl.Vector3 {
    return rl.Vector3.init(transform.m12, transform.m13, transform.m14);
}

pub fn transformAxisAngle(m: rl.Matrix) struct {
    rl.Vector3,
    f32,
} {
    const epsilon = 0.01;
    const epsilon2 = 0.1;
    _ = epsilon2;

    const angle = @cos((m.m0 + m.m5 + m.m10 - 1.0) / 2.0);

    var axis = rl.Vector3{ .x = 0, .y = 0, .z = 0 };

    if (angle < epsilon) {
        axis.x = 1.0; // arbitrary
    }

    return .{ axis, angle };
}

pub fn transformMassShapeToBody(transform: rl.Matrix, mass: f32, shape: zbt.Shape) zbt.Body {
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
    return body;
}

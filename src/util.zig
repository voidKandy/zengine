const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const zm = @import("zmath");

/// **Position** = (x = m12, y = m13, z = m14)
/// ```
/// | m0  m4  m8   m12 |
/// | m1  m5  m9   m13 |
/// | m2  m6  m10  m14 |
/// | m3  m7  m11  m15 |
/// ```
pub fn extractPosition(transform: rl.Matrix) rl.Vector3 {
    return rl.Vector3.init(transform.m12, transform.m13, transform.m14);
}

pub fn extractAxisAngle(m: rl.Matrix) struct {
    rl.Vector3,
    f32,
} {
    // Strip translation components
    const stripped = rl.Matrix{
        .m0 = m.m0,
        .m1 = m.m1,
        .m2 = m.m2,
        .m3 = m.m3,
        .m4 = m.m4,
        .m5 = m.m5,
        .m6 = m.m6,
        .m7 = m.m7,
        .m8 = m.m8,
        .m9 = m.m9,
        .m10 = m.m10,
        .m11 = m.m11,
        .m12 = 0.0,
        .m13 = 0.0,
        .m14 = 0.0,
        .m15 = m.m15,
    };

    // Convert to quaternion using zmath for stability
    // x,y,z,w
    const quat = zm.quatFromMat(@as(zm.Mat, @bitCast(stripped)));

    // Compute angle
    const angle = 2.0 * std.math.acos(quat[3]);

    // Compute axis
    const s = @sqrt(1.0 - quat[3] * quat[3]);
    const axis = if (s < 0.001) rl.Vector3.init(1.0, 0.0, 0.0) else rl.Vector3{
        .x = quat[0] / s,
        .y = quat[1] / s,
        .z = quat[2] / s,
    };

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

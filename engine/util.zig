const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const zm = @import("zmath");

pub fn meshToBulletShape(mesh: rl.Mesh) !zbt.TriangleMeshShape {
    var shape = zbt.initTriangleMeshShape();
    const vertex_ptr: *const anyopaque = @ptrCast(@alignCast(mesh.vertices));
    const vertex_stride: u32 = 3 * @sizeOf(f32); // Each vertex has 3 floats (x, y, z)
    const vertex_count: u32 = @intCast(mesh.vertexCount);
    const index_ptr: *const anyopaque = @ptrCast(@alignCast(mesh.indices));
    const triangle_stride: u32 = 3 * @sizeOf(c_ushort); // 3 indices per triangle
    const triangle_count: u32 = @intCast(mesh.triangleCount);
    shape.addIndexVertexArray(
        triangle_count,
        index_ptr,
        triangle_stride,
        vertex_count,
        vertex_ptr,
        vertex_stride,
    );

    return shape;
}

/// uses ray-casting to check if a point is within a polygon.
/// This will cast a ray from the point **TO THE RIGHT** and check if it intersects the polygon.
/// If it intersects the polygon an **ODD** number of times, the point is inside the polygon
/// If it intersects the polygon an **EVEN** number of times, the point is outside the polygon
/// As usual, vertices should be passed in either clockwise or counter clockwise order
pub fn pointInPolygon(p: rl.Vector2, vertices: []rl.Vector2) bool {
    var inside = false;
    var j = vertices.len - 1;
    for (vertices, 0..) |vi, i| {
        const vj = vertices[j];

        if ((vi.y > p.y) != (vj.y > p.y)) {
            const intersect_x =
                (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x;

            if (p.x < intersect_x) {
                inside = !inside;
            }
        }

        j = i;
    }

    return inside;
}

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

/// Line intersection utilities
/// https://www.geeksforgeeks.org/check-if-two-given-line-segments-intersect/
/// `Orientation` of an ordered triplet of points can be one of the following
/// `cw` & `ccw` *should* be self explanatory
/// **Collinear** just means the points do not create a cycle
pub const Orientation = enum {
    /// clockwise
    cw,
    /// counter-clockwise
    ccw,
    /// collinear
    col,

    /// function to find orientation of ordered triplet of points (p, q, r)
    fn get(
        p: rl.Vector2,
        q: rl.Vector2,
        r: rl.Vector2,
    ) Orientation {
        const val: f32 = (q.y - p.y) * (r.x - q.x) -
            (q.x - p.x) * (r.y - q.y);

        if (val == 0.0)
            return .col;
        if (val > 0.0)
            return .cw;
        return .ccw;
    }
};

/// `start` and `end` are totally interchangable
pub const LineSegment = struct {
    start: rl.Vector2,
    end: rl.Vector2,

    /// Checks if point is on line segment
    pub fn pointOn(self: @This(), point: rl.Vector2) bool {
        return (point.x <= @max(self.start.x, self.end.x) and
            point.x >= @min(self.start.x, self.end.x) and
            point.y <= @max(self.start.y, self.end.y) and
            point.y >= @min(self.start.y, self.end.y));
    }

    /// The idea is to use orientation of lines to determine whether they intersect or not. Two line segments [p1, q1] and [p2, q2] intersects if and only if one of the following two conditions is verified:
    ///
    /// 1. General Case:
    ///
    ///     [p1, q1, p2] and [p1, q1, q2] have different orientations.
    ///     [p2, q2, p1] and [p2, q2, q1] have different orientations.
    ///
    /// 2. Special Case:
    ///
    ///     [p1, q1, p2], [p1, q1, q2], [p2, q2, p1], and [p2, q2, q1] are all collinear.
    ///     The x-projections of [p1, q1] and [p2, q2] intersect.
    ///     The y-projections of [p1, q1] and [p2, q2] intersect.
    pub fn intersects(self: @This(), other: @This()) bool {

        // find the four orientations needed
        // for general and special cases
        const o1 = Orientation.get(self.start, self.end, other.start);
        const o2 = Orientation.get(self.start, self.end, other.end);
        const o3 = Orientation.get(other.start, other.end, self.start);
        const o4 = Orientation.get(other.start, other.end, self.end);

        // general case
        if (@intFromEnum(o1) != @intFromEnum(o2) and @intFromEnum(o3) != @intFromEnum(o4))
            return true;

        // special cases
        // `self.start`, `self.end` and `other.start` are collinear and `other.start` is on `self`
        if (o1 == .col and self.pointOn(other.start))
            return true;

        // `self.start`, `self.end` and `other.end` are collinear and `other.end` is on `self`
        if (o2 == .col and self.pointOn(other.end))
            return true;

        // `other.start`, `other.end` and `self.start` are collinear and `self.start` is on `other`
        if (o3 == .col and other.pointOn(self.start))
            return true;

        // p2, q2 and q1 are collinear and q1 lies on segment p2q2
        // `other.start`, `other.end` and `self.end` are collinear and `self.end` is on `other`
        if (o4 == .col and other.pointOn(self.end))
            return true;

        return false;
    }
};

test "line segment intersection tests" {
    const expect = std.testing.expect;

    const A = rl.Vector2.init(0, 0);
    const B = rl.Vector2.init(4, 4);
    const C = rl.Vector2.init(0, 4);
    const D = rl.Vector2.init(4, 0);
    const E = rl.Vector2.init(5, 5);
    const F = rl.Vector2.init(10, 10);
    const G = rl.Vector2.init(2, 2);
    const H = rl.Vector2.init(6, 6);
    const I = rl.Vector2.init(0, 1);
    const J = rl.Vector2.init(4, 5);
    const epsilon = 1e-5;
    const K = rl.Vector2.init(0, 0);
    const L = rl.Vector2.init(1, 1);
    const M = rl.Vector2.init(0, 1 + epsilon);
    const N = rl.Vector2.init(1, 2 + epsilon);

    // 1. Simple intersection (X shape)
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = B };
        break :blk seg.intersects(LineSegment{ .start = C, .end = D });
    });

    // 2. Non-intersecting (clearly separate)
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = B };
        break :blk !seg.intersects(LineSegment{ .start = E, .end = F });
    });

    // 3. Collinear, overlapping
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = F };
        break :blk seg.intersects(LineSegment{ .start = G, .end = H });
    });

    // 4. Collinear, non-overlapping
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = G };
        break :blk !seg.intersects(LineSegment{ .start = H, .end = F });
    });

    // 5. Endpoint touching
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = G };
        break :blk seg.intersects(LineSegment{ .start = G, .end = F });
    });

    // 6. Parallel, non-overlapping
    try expect(blk: {
        const seg = LineSegment{ .start = A, .end = B };
        break :blk !seg.intersects(LineSegment{ .start = I, .end = J });
    });

    // 7. Very close but not intersecting (test floating-point tolerance)
    try expect(blk: {
        const seg = LineSegment{ .start = K, .end = L };
        break :blk !seg.intersects(LineSegment{ .start = M, .end = N });
    });

    std.debug.print(
        \\ Line Segment Intersection Tests PASSED
        \\
    , .{});
}

test "point in polygon" {
    const allocator = std.testing.allocator;
    const point = rl.Vector2{
        .x = 0.0,
        .y = 0.0,
    };

    var vertices = std.ArrayList(rl.Vector2).init(allocator);
    defer vertices.deinit();

    for (&[_]rl.Vector2{
        .{ .x = -1.0, .y = 1.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 1.0, .y = -1.0 },
        .{ .x = -1.0, .y = -1.0 },
    }) |v| {
        try vertices.append(v);
    }

    try std.testing.expectEqual(true, pointInPolygon(point, vertices.items));
}

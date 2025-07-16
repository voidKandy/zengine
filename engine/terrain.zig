const std = @import("std");
const core = @import("root");
const rl = @import("raylib");
const core = @import("engine_core");


pub const Pixel = struct {
    r: u32,
    g: u32,
    b: u32,
};

pub fn genMaskedImageMesh(
    allocator: std.mem.Allocator,
    /// Row Major Heightmap
    heightmap: []Pixel,
    size: rl.Vector3,
    /// The polygon the describes the mask over the heightmap image.
    /// SHOULD NOT INCLUDE THE CENTER
    /// BAD TYPE
    mask: []const rl.Vector2,
    /// This defines how many more points we need to add to the perimeter.
    /// MUST BE AN EVEN NUMBER
    /// 2 Is a good default
    /// Example:
    /// If this is set to 2 and the mask is a square
    /// The square will have 8 points along it's perimeter
    resolution_scale: usize,
    // ) !rl.Mesh {
    // right now just returns triangles
) !rl.Mesh {
    _ = heightmap;
    _ = size;

    var vertices = std.ArrayList(rl.Vector3).init(allocator);
    // defer vertices.deinit();

    var normals = std.ArrayList(rl.Vector3).init(allocator);
    // defer normals.deinit();

    var uvs = std.ArrayList(rl.Vector2).init(allocator);
    // defer uvs.deinit();

    // var indices = std.ArrayList(u16).init(allocator);

    if (@mod(resolution_scale, 2) != 0)
        return error.InvalidResolutionScale;

    const n = mask.len;
    var outer_perimeter = try allocator.alloc(rl.Vector2, n * resolution_scale);
    // defer call should be removed later
    defer allocator.free(outer_perimeter);

    std.log.warn(
        \\ creating outer perimeter with {d} vertices
        \\
    , .{n * resolution_scale});
    var amt: usize = 0;

    for (mask, 0..) |vertex, i| {
        const next_vertex =
            if (i + 1 == n)
                mask[0]
            else
                mask[i + 1];

        const mid = midpoint(vertex, next_vertex);
        outer_perimeter[amt] = vertex;
        amt += 1;
        outer_perimeter[amt] = mid;
        amt += 1;
    }

    const polygon_center = rl.Vector2{
        .x = 0.0,
        .y = 0.0,
    };

    const scale: f32 = 0.8;
    const inner_perimeter = try allocator.alloc(rl.Vector2, outer_perimeter.len);
    // defer call should be removed later
    defer allocator.free(inner_perimeter);

    for (outer_perimeter, inner_perimeter) |vertex, *v| {
        v.* = rl.Vector2{
            .x = polygon_center.x + (vertex.x - polygon_center.x) * scale,
            .y = polygon_center.y + (vertex.y - polygon_center.y) * scale,
        };
    }

    for (outer_perimeter, inner_perimeter, 0..) |outer_v, inner_v, i| {
        const other_idx =
            if (i + 1 >= n)
                0
            else
                i + 1;
        if (@mod(i, 2) == 0) {
            const other = outer_perimeter[other_idx];
            const v1 = rl.Vector3{
                .x = outer_v.x,
                // we'll get this correctly later
                .y = 1.0,
                .z = outer_v.y,
            };
            const v2 = rl.Vector3{
                .x = inner_v.x,
                .y = 1.0,
                .z = inner_v.y,
            };

            const v3 = rl.Vector3{
                .x = other.x,
                .y = 1.0,
                .z = other.y,
            };
            try vertices.append(v1);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(outer_v));

            try vertices.append(v2);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(inner_v));

            try vertices.append(v3);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(other));
        } else {
            const other = inner_perimeter[other_idx];
            const v1 = rl.Vector3{
                .x = inner_v.x,
                // we'll get this correctly later
                .y = 1.0,
                .z = inner_v.y,
            };
            const v2 = rl.Vector3{
                .x = outer_v.x,
                .y = 1.0,
                .z = outer_v.y,
            };
            const v3 = rl.Vector3{
                .x = other.x,
                .y = 1.0,
                .z = other.y,
            };
            try vertices.append(v1);
            try uvs.append(vec2ToUV(inner_v));
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)

            try vertices.append(v2);
            try uvs.append(vec2ToUV(outer_v));
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)

            try vertices.append(v3);
            try uvs.append(vec2ToUV(other));
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
        }
    }

    const mesh = try allocator.create(rl.Mesh);
    mesh.* = std.mem.zeroInit(rl.Mesh, .{});

    mesh.*.vertices = @as([*]f32, @ptrCast(try allocator.alloc(f32, vertices.items.len * 3)));
    mesh.*.normals = @as([*]f32, @ptrCast(try allocator.alloc(f32, normals.items.len * 3)));
    mesh.*.texcoords = @as([*]f32, @ptrCast(try allocator.alloc(f32, uvs.items.len * 2)));

    for (vertices.items, 0..) |v, i| {
        mesh.vertices[i * 3 + 0] = v.x;
        mesh.vertices[i * 3 + 1] = v.y;
        mesh.vertices[i * 3 + 2] = v.z;
    }
    for (normals.items, 0..) |nor, i| {
        mesh.normals[i * 3 + 0] = nor.x;
        mesh.normals[i * 3 + 1] = nor.y;
        mesh.normals[i * 3 + 2] = nor.z;
    }
    for (uvs.items, 0..) |uv, i| {
        mesh.texcoords[i * 2 + 0] = uv.x;
        mesh.texcoords[i * 2 + 1] = uv.y;
    }
    return mesh.*;
}

fn midpoint(v1: rl.Vector2, v2: rl.Vector2) rl.Vector2 {
    const v = rl.Vector2{ .x = (v1.x + v2.x) / 2.0, .y = (v1.y + v2.y) / 2.0 };
    return v;
}

fn vec2ToUV(v: rl.Vector2) rl.Vector2 {
    return rl.Vector2{
        .x = (v.x + 0.5),
        .y = 1.0 - (v.y + 0.5),
    };
}

test "terrain!" {
    const allocator = std.testing.allocator;

    const heightmap = try allocator.alloc(Pixel, 256 * 256);
    defer allocator.free(heightmap);

    @memset(heightmap, Pixel{
        .r = 255,
        .g = 255,
        .b = 255,
    });

    const mask = [_]rl.Vector2{
        .{ .x = 0.5, .y = 0.5 },
        .{ .x = -0.5, .y = 0.5 },
        // .{ .x = -0.7, .y = 0.0 },
        .{ .x = -0.5, .y = -0.5 },
        .{ .x = 0.5, .y = -0.5 },
    };

    // const image = try rl.loadImage("resources/heightmap.png");
    // defer rl.unloadImage(image);
    //
    const size = rl.Vector3.init(16.0, 4.0, 16.0);

    const mesh =
        try genMaskedImageMesh(allocator, heightmap, size, &mask, 2);
    _ = mesh;
    // defer idcs.deinit();
    // try std.testing.expectError(error.Unimplemented, result);
    // @panic("");
    return;


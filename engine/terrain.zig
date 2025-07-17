const std = @import("std");
const core = @import("root");
const rl = @import("raylib");
const engine = @import("root.zig");

fn sampleColor(uv: rl.Vector2, width: usize, height: usize, colors: []rl.Color) rl.Color {
    std.debug.assert(uv.x <= 1.0 and uv.x >= 0.0 and
        uv.y <= 1.0 and uv.y >= 0.0);
    const x_f = uv.x * @as(f32, @floatFromInt(width - 1));
    const z_f = uv.y * @as(f32, @floatFromInt(height - 1));

    const x0 = @min(@as(usize, @intFromFloat(x_f)), width - 1);
    const z0 = @min(@as(usize, @intFromFloat(z_f)), height - 1);
    const x1 = @min(x0 + 1, width - 1);
    const z1 = @min(z0 + 1, height - 1);

    const idx00 = z0 * width + x0;
    const idx10 = z0 * width + x1;
    const idx01 = z1 * width + x0;
    const idx11 = z1 * width + x1;

    var c_r: u32 = 0;
    var c_g: u32 = 0;
    var c_b: u32 = 0;
    for (&[_]usize{ idx00, idx10, idx01, idx11 }) |idx| {
        const pixel = colors[idx];
        c_r += @intCast(pixel.r);
        c_g += @intCast(pixel.g);
        c_b += @intCast(pixel.b);
    }

    const color = rl.Color{
        .r = @intCast(c_r / 4),
        .g = @intCast(c_g / 4),
        .b = @intCast(c_b / 4),
        .a = 255,
    };

    return color;
}

pub fn genMaskedImageMesh(
    allocator: std.mem.Allocator,
    /// Row Major Heightmap
    heightmap: rl.Image,
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
    const map_width: usize = @intCast(heightmap.width);
    const map_height: usize = @intCast(heightmap.height);
    std.log.warn(
        \\ WIDTH: {d}
        \\ HEIGHT: {d}
        \\
    , .{ map_width, map_height });

    const colors = try rl.loadImageColors(heightmap);
    defer rl.unloadImageColors(colors);

    var vertices = std.ArrayList(rl.Vector3).init(allocator);
    // defer vertices.deinit();

    var normals = std.ArrayList(rl.Vector3).init(allocator);
    // defer normals.deinit();

    var uvs = std.ArrayList(rl.Vector2).init(allocator);
    // defer uvs.deinit();

    var indices = std.ArrayList(u16).init(allocator);

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

    const offset_scale: f32 = 0.8;
    const offset_perimeter = try allocator.alloc(rl.Vector2, outer_perimeter.len);
    // defer call should be removed later
    defer allocator.free(offset_perimeter);

    for (outer_perimeter, offset_perimeter) |vertex, *v| {
        v.* = rl.Vector2{
            .x = polygon_center.x + (vertex.x - polygon_center.x) * offset_scale,
            .y = polygon_center.y + (vertex.y - polygon_center.y) * offset_scale,
        };
    }

    std.log.warn(
        \\
        \\ PERIMETERS:
        \\ OG:
        \\ {any}
        \\ OFFSET:
        \\ {any}
        \\
    , .{ outer_perimeter, offset_perimeter });

    std.debug.assert(outer_perimeter.len == offset_perimeter.len);

    var i: usize = 0;
    while (i < outer_perimeter.len) {
        const outer_uv0 = outer_perimeter[i];
        const offset_uv0 = offset_perimeter[i];
        const other_idx =
            if (i + 1 >= outer_perimeter.len)
                0
            else
                i + 1;
        const outer_uv1 = outer_perimeter[other_idx];
        const offset_uv1 = offset_perimeter[other_idx];

        const outer_v0 = rl.Vector3{
            .x = outer_uv0.x * size.x,
            .y = (@as(f32, @floatFromInt(sampleColor(vec2ToUV(outer_uv0), map_width, map_height, colors).r)) / 255.0) * size.y,
            .z = outer_uv0.y * size.z,
        };
        const offset_v0 = rl.Vector3{
            .x = offset_uv0.x * size.x,
            .y = (@as(f32, @floatFromInt(sampleColor(vec2ToUV(offset_uv0), map_width, map_height, colors).r)) / 255.0) * size.y,
            .z = offset_uv0.y * size.z,
        };

        const outer_v1 = rl.Vector3{
            .x = outer_uv1.x * size.x,
            .y = (@as(f32, @floatFromInt(sampleColor(vec2ToUV(outer_uv1), map_width, map_height, colors).r)) / 255.0) * size.y,
            .z = outer_uv1.y * size.z,
        };
        const offset_v1 = rl.Vector3{
            .x = offset_uv1.x * size.x,
            .y = (@as(f32, @floatFromInt(sampleColor(vec2ToUV(offset_uv1), map_width, map_height, colors).r)) / 255.0) * size.y,
            .z = offset_uv1.y * size.z,
        };

        std.log.warn(
            \\
            \\ outer_v0:
            \\ {any}
            \\ offset_v0:
            \\ {any}
            \\ outer_v1:
            \\ {any}
            \\ offset_v1:
            \\ {any}
            \\
        , .{
            outer_v0,
            offset_v0,
            outer_v1,
            offset_v1,
        });

        {
            try vertices.append(outer_v0);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(outer_uv0));
            try vertices.append(offset_v0);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(offset_uv0));
            try vertices.append(outer_v1);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(outer_uv1));
        }

        {
            try vertices.append(offset_v0);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(offset_uv0));
            try vertices.append(offset_v1);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(offset_uv1));
            try vertices.append(outer_v1);
            try normals.append(.{ .x = 0, .y = 1, .z = 0 }); // Up normals (basic)
            try uvs.append(vec2ToUV(outer_uv1));
        }

        const base_idx = @as(u16, @intCast(vertices.items.len - 6));
        for (0..6) |k| {
            try indices.append(base_idx + @as(u16, @intCast(k)));
        }

        i += 1;
    }

    const mesh = try allocator.create(rl.Mesh);
    mesh.* = std.mem.zeroInit(rl.Mesh, .{});

    mesh.*.vertices = @as([*]f32, @ptrCast(try allocator.alloc(f32, vertices.items.len * 3)));
    mesh.*.normals = @as([*]f32, @ptrCast(try allocator.alloc(f32, normals.items.len * 3)));
    mesh.*.texcoords = @as([*]f32, @ptrCast(try allocator.alloc(f32, uvs.items.len * 2)));
    mesh.*.indices = @as([*]u16, @ptrCast(try allocator.alloc(u16, indices.items.len)));

    for (vertices.items, 0..) |v, k| {
        mesh.vertices[k * 3 + 0] = v.x;
        mesh.vertices[k * 3 + 1] = v.y;
        mesh.vertices[k * 3 + 2] = v.z;
    }
    for (normals.items, 0..) |nor, k| {
        mesh.normals[k * 3 + 0] = nor.x;
        mesh.normals[k * 3 + 1] = nor.y;
        mesh.normals[k * 3 + 2] = nor.z;
    }
    for (uvs.items, 0..) |uv, k| {
        mesh.texcoords[k * 2 + 0] = uv.x;
        mesh.texcoords[k * 2 + 1] = uv.y;
    }
    std.mem.copyForwards(u16, mesh.indices[0..indices.items.len], indices.items);

    mesh.*.vertexCount = @as(c_int, @intCast(vertices.items.len));
    mesh.*.triangleCount = @as(c_int, @intCast(indices.items.len / 3));

    return mesh.*;
}

fn midpoint(v1: rl.Vector2, v2: rl.Vector2) rl.Vector2 {
    const v = rl.Vector2{ .x = (v1.x + v2.x) / 2.0, .y = (v1.y + v2.y) / 2.0 };
    return v;
}

/// Masks are defined in normalized space
/// Which covers the range -1.0 to 1.0
/// We need to convert this to UV space
/// Which ranges from 0 to 1.0
/// The Y also needs to be flipped because UV space has Y INCREASE as we go DOWN the grid
fn vec2ToUV(v: rl.Vector2) rl.Vector2 {
    return rl.Vector2{
        .x = (v.x + 0.5),
        .y = 1.0 - (v.y + 0.5),
    };
}

// test "terrain!" {
//     const allocator = std.testing.allocator;

//     const heightmap = try allocator.alloc(Pixel, 256 * 256);
//     defer allocator.free(heightmap);

//     @memset(heightmap, Pixel{
//         .r = 255,
//         .g = 255,
//         .b = 255,
//     });

//     const mask = [_]rl.Vector2{
//         .{ .x = 0.5, .y = 0.5 },
//         .{ .x = -0.5, .y = 0.5 },
//         // .{ .x = -0.7, .y = 0.0 },
//         .{ .x = -0.5, .y = -0.5 },
//         .{ .x = 0.5, .y = -0.5 },
//     };

//     // const image = try rl.loadImage("resources/heightmap.png");
//     // defer rl.unloadImage(image);
//     //
//     const size = rl.Vector3.init(16.0, 4.0, 16.0);

//     const mesh =
//         try genMaskedImageMesh(allocator, heightmap, size, &mask, 2);
//     _ = mesh;
//     // defer idcs.deinit();
//     // try std.testing.expectError(error.Unimplemented, result);
//     // @panic("");
//     return;
// }

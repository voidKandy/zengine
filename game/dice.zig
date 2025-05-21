const rl = @import("raylib");
const gl = rl.gl;
const std = @import("std");
const zbt = @import("zbullet");
const engine = @import("engine_core");
const warn = std.log.warn;
const Shape = zbt.Shape;
const Allocator = std.mem.Allocator;

pub const DieType =
    enum {
        six,
        // twenty,
        // four,
        // two?,

        const Error = error{};
        const CreateMeshFunc = *const fn (args: anytype) Error!rl.Mesh;
        pub fn createMeshFunc(self: @This()) CreateMeshFunc {
            switch (self) {
                .six => {
                    return struct {
                        /// Cube creation function take a tuple of 3 `f32`
                        /// `width`, `height`, `length`
                        fn _wrapper(dims: anytype) Error!rl.Mesh {
                            return rl.genMeshCube(dims.@"0", dims.@"1", dims.@"2");
                        }
                    }._wrapper;
                },
            }
        }

        /// NEEDS TO BE GENERALIZED
        pub fn whichFaceUp(transform: rl.Matrix) u32 {
            // indices correspond with face values
            const rotations = [_]rl.Matrix{
                rl.Matrix.rotateX(-std.math.pi / 2.0),
                rl.Matrix.rotateZ(std.math.pi / 2.0),
                rl.Matrix.identity(),
                rl.Matrix.rotateX(std.math.pi),
                rl.Matrix.rotateZ(-std.math.pi / 2.0),
                rl.Matrix.rotateX(std.math.pi / 2.0),
            };

            var best_index: usize = 0;
            var best_error: f32 = std.math.inf(f32);

            for (rotations, 0..) |expected, i| {
                const diff = matrixError(expected, transform);
                if (diff < best_error) {
                    best_error = diff;
                    best_index = i;
                }
            }

            return @as(u32, @intCast(best_index + 1)); // Return 1-based face index

        }
        fn matrixError(a: rl.Matrix, b: rl.Matrix) f32 {
            var sum: f32 = 0.0;
            for (0..16) |i| {
                const da = @as([*]const f32, @ptrCast(&a))[i];
                const db = @as([*]const f32, @ptrCast(&b))[i];
                const d = da - db;
                sum += d * d;
            }
            return sum;
        }
    };

pub fn genD6Faces(
    size: f32,
) [6]rl.Mesh {
    const halfsize = size / 2.0;
    const third: f32 = 1.0 / 3.0;
    const neg_halfsize = halfsize * -1.0;

    const faces_data = [6]struct {
        normal: [3]f32,
        coords: [4]struct {
            tex_coords: [2]f32,
            vertex_coords: [3]f32,
        },
    }{
        // Front Face (+Z)
        // 1
        .{
            .normal = [_]f32{ 0.0, 0.0, 1.0 },
            .coords = .{
                // start at the bottom left corner
                // winds counter clockwise
                .{ .tex_coords = .{ 0.0, third }, .vertex_coords = .{ neg_halfsize, neg_halfsize, halfsize } },
                .{ .tex_coords = .{ 0.5, third }, .vertex_coords = .{ halfsize, neg_halfsize, halfsize } },
                .{ .tex_coords = .{ 0.5, 0.0 }, .vertex_coords = .{ halfsize, halfsize, halfsize } },
                .{ .tex_coords = .{ 0.0, 0.0 }, .vertex_coords = .{ neg_halfsize, halfsize, halfsize } },
            },
        },
        // Back Face (-Z)
        // 6
        .{ .normal = [_]f32{ 0.0, 0.0, -1.0 }, .coords = .{
            .{ .tex_coords = .{ 0.5, 1.0 }, .vertex_coords = .{ neg_halfsize, neg_halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, 1.0 }, .vertex_coords = .{ neg_halfsize, halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, third * 2.0 }, .vertex_coords = .{ halfsize, halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 0.5, third * 2.0 }, .vertex_coords = .{ halfsize, neg_halfsize, neg_halfsize } },
        } },
        // Top Face (+Y)
        // 3
        .{ .normal = [_]f32{ 0.0, 1.0, 0.0 }, .coords = .{
            .{ .tex_coords = .{ 0.0, third * 2.0 }, .vertex_coords = .{ neg_halfsize, halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 0.5, third * 2.0 }, .vertex_coords = .{ neg_halfsize, halfsize, halfsize } },
            .{ .tex_coords = .{ 0.5, third }, .vertex_coords = .{ halfsize, halfsize, halfsize } },
            .{ .tex_coords = .{ 0.0, third }, .vertex_coords = .{ halfsize, halfsize, neg_halfsize } },
        } },
        // Bottom Face (-Y)
        // 4
        .{ .normal = [_]f32{ 0.0, -1.0, 0.0 }, .coords = .{
            .{ .tex_coords = .{ 0.5, third * 2.0 }, .vertex_coords = .{ neg_halfsize, neg_halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, third * 2.0 }, .vertex_coords = .{ halfsize, neg_halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, third }, .vertex_coords = .{ halfsize, neg_halfsize, halfsize } },
            .{ .tex_coords = .{ 0.5, third }, .vertex_coords = .{ neg_halfsize, neg_halfsize, halfsize } },
        } },
        // Right Face (+X)
        // 2
        .{ .normal = [_]f32{ 1.0, 0.0, 0.0 }, .coords = .{
            .{ .tex_coords = .{ 0.5, third }, .vertex_coords = .{ halfsize, neg_halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, third }, .vertex_coords = .{ halfsize, halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 1.0, 0.0 }, .vertex_coords = .{ halfsize, halfsize, halfsize } },
            .{ .tex_coords = .{ 0.5, 0.0 }, .vertex_coords = .{ halfsize, neg_halfsize, halfsize } },
        } },
        // Left Face (-X)
        // 5
        .{ .normal = [_]f32{ -1.0, 0.0, 0.0 }, .coords = .{
            .{ .tex_coords = .{ 0.0, 1.0 }, .vertex_coords = .{ neg_halfsize, neg_halfsize, neg_halfsize } },
            .{ .tex_coords = .{ 0.5, 1.0 }, .vertex_coords = .{ neg_halfsize, neg_halfsize, halfsize } },
            .{ .tex_coords = .{ 0.5, third * 2.0 }, .vertex_coords = .{ neg_halfsize, halfsize, halfsize } },
            .{ .tex_coords = .{ 0.0, third * 2.0 }, .vertex_coords = .{ neg_halfsize, halfsize, neg_halfsize } },
        } },
    };

    var meshes: [6]rl.Mesh = undefined;
    for (&meshes, faces_data) |*mesh, d| {
        const vertices = [_]f32{
            d.coords[0].vertex_coords[0], d.coords[0].vertex_coords[1], d.coords[0].vertex_coords[2],
            d.coords[1].vertex_coords[0], d.coords[1].vertex_coords[1], d.coords[1].vertex_coords[2],
            d.coords[2].vertex_coords[0], d.coords[2].vertex_coords[1], d.coords[2].vertex_coords[2],

            d.coords[0].vertex_coords[0], d.coords[0].vertex_coords[1], d.coords[0].vertex_coords[2],
            d.coords[2].vertex_coords[0], d.coords[2].vertex_coords[1], d.coords[2].vertex_coords[2],
            d.coords[3].vertex_coords[0], d.coords[3].vertex_coords[1], d.coords[3].vertex_coords[2],
        };

        const texcoords = [_]f32{
            d.coords[0].tex_coords[0], d.coords[0].tex_coords[1],
            d.coords[1].tex_coords[0], d.coords[1].tex_coords[1],
            d.coords[2].tex_coords[0], d.coords[2].tex_coords[1],

            d.coords[0].tex_coords[0], d.coords[0].tex_coords[1],
            d.coords[2].tex_coords[0], d.coords[2].tex_coords[1],
            d.coords[3].tex_coords[0], d.coords[3].tex_coords[1],
        };

        const normals = [_]f32{
            // repeat normal per vertex (6 total)
            d.normal[0], d.normal[1], d.normal[2],
            d.normal[0], d.normal[1], d.normal[2],
            d.normal[0], d.normal[1], d.normal[2],
            d.normal[0], d.normal[1], d.normal[2],
            d.normal[0], d.normal[1], d.normal[2],
            d.normal[0], d.normal[1], d.normal[2],
        };
        const newmesh = rl.Mesh{
            .vertexCount = 6,
            .triangleCount = 2,
            .vertices = @constCast(@ptrCast(&vertices)),
            .texcoords = @constCast(@ptrCast(&texcoords)),
            .normals = @constCast(@ptrCast(&normals)),
            .texcoords2 = null,
            .tangents = null,
            .colors = null,
            .indices = null,
            .animVertices = null,
            .animNormals = null,
            .boneIds = null,
            .boneWeights = null,
            .boneMatrices = null,
            .boneCount = 0,
            .vaoId = 0,
            .vboId = null,
        };
        mesh.* = newmesh;
        rl.uploadMesh(mesh, false);
    }
    return meshes;
}

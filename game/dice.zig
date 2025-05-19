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

fn drawCubeWithTransformMatrix(texture: rl.Texture2D, transform: rl.Matrix, size: f32, color: rl.Color) void {
    const halfsize = size / 2.0;
    const third: f32 = 1.0 / 3.0;
    const neg_halfsize = halfsize * -1.0;
    gl.rlSetTexture(texture.id);
    gl.rlBegin(gl.rl_quads);
    gl.rlColor4ub(color.r, color.g, color.b, color.a);

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

    for (faces_data) |d| {
        const normal =
            rl.Vector3{
                .x = d.normal[0] * transform.m0 + d.normal[1] * transform.m4 + d.normal[2] * transform.m8,
                .y = d.normal[0] * transform.m1 + d.normal[1] * transform.m5 + d.normal[2] * transform.m9,
                .z = d.normal[0] * transform.m2 + d.normal[1] * transform.m6 + d.normal[2] * transform.m10,
            };

        gl.rlNormal3f(
            normal.x,
            normal.y,
            normal.z,
        );

        for (d.coords) |coords| {
            const translation = rl.Matrix.translate(
                coords.vertex_coords[0],
                coords.vertex_coords[1],
                coords.vertex_coords[2],
            );

            const vertex_coords = engine.util.extractPosition(rl.Matrix.multiply(translation, transform));

            gl.rlTexCoord2f(
                coords.tex_coords[0],
                coords.tex_coords[1],
            );
            gl.rlVertex3f(
                vertex_coords.x,
                vertex_coords.y,
                vertex_coords.z,
            );
        }
    }

    gl.rlEnd();

    gl.rlSetTexture(0);
}

fn getDieMeshes(
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
    for (0.., faces_data) |meshidx, d| {
        const vertices = [_:0]f32{
            d.coords[0].vertex_coords[0],
            d.coords[0].vertex_coords[1],
            d.coords[0].vertex_coords[2],
            d.coords[1].vertex_coords[0],
            d.coords[1].vertex_coords[1],
            d.coords[1].vertex_coords[2],
            d.coords[2].vertex_coords[0],
            d.coords[2].vertex_coords[1],
            d.coords[2].vertex_coords[2],
            d.coords[3].vertex_coords[0],
            d.coords[3].vertex_coords[1],
            d.coords[3].vertex_coords[2],
            0,
        };
        const texcoords = [_:0]f32{
            d.coords[0].tex_coords[0],
            d.coords[0].tex_coords[1],
            d.coords[1].tex_coords[0],
            d.coords[1].tex_coords[1],
            d.coords[2].tex_coords[0],
            d.coords[2].tex_coords[1],
            d.coords[3].tex_coords[0],
            d.coords[3].tex_coords[1],
            0,
        };
        const normals = [_:0]f32{ d.normal[0], d.normal[1], d.normal[2], 0 };
        const mesh = rl.Mesh{
            .vertexCount = d.coords.len * 3,
            .triangleCount = d.coords.len,
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

        meshes[meshidx] = mesh;
    }
    return meshes;
}

/// Each die has two "layers"
pub fn Die(comptime numbers_atlas_path: [:0]const u8) type {
    return struct {
        _type: DieType,
        /// Mesh 0 is the inner cube mesh
        /// The other 6 are each face with a texture
        meshes: [7]rl.Mesh,
        /// This is the material applied to Mesh 0
        material: rl.Material,
        /// This is the texture mapped onto the other 6 Meshes
        faces_texture: rl.Texture2D,

        fn zeroTermAtlasPath() [:0]const u8 {
            var arr: [numbers_atlas_path.len + 1:0]u8 = undefined;
            @memset(&arr, 0);
            for (&arr, 0..) |*v, i| {
                if (i < numbers_atlas_path.len) {
                    const byte = numbers_atlas_path[i];
                    v.* = byte;
                }
            }
            return &arr;
        }

        /// Each `DieType` has their own initialization function arguments which are passed here as `args`
        /// `.six` - `struct {f32, f32, f32}`
        pub fn new(material: rl.Material, _type: DieType, args: anytype) rl.RaylibError!@This() {
            const numbers_atlas_img = rl.loadImage(numbers_atlas_path) catch @panic("INVALID ATLAS PATH");
            const quad_tex = rl.loadTextureFromImage(numbers_atlas_img) catch @panic("COULD NOT GET TEXTURE FROM ATLAS IMAGE");
            const mesh = try _type.createMeshFunc()(args);
            const meshes = getDieMeshes(args.@"0");
            var all_meshes: [7]rl.Mesh = undefined;
            all_meshes[0] = mesh;

            for (meshes, 1..) |m, i| {
                all_meshes[i] = m;
            }

            return @This(){
                ._type = _type,
                .meshes = all_meshes,
                .material = material,
                .faces_texture = quad_tex,
            };
        }

        pub fn draw(self: *@This(), world_transform: rl.Matrix) !void {
            std.log.warn(
                \\ Drawing Dice
                \\
            , .{});
            self.meshes[0].draw(self.material, world_transform);

            var other_meshes_material = try rl.loadMaterialDefault();
            other_meshes_material.maps[0].texture = self.faces_texture;
            for (self.meshes[1..]) |mesh| {
                mesh.draw(other_meshes_material, world_transform);
            }
            switch (self._type) {
                .six => drawCubeWithTransformMatrix(self.faces_texture, world_transform, 1.001, rl.Color.white),
            }
        }
    };
}

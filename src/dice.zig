const rl = @import("raylib");
const gl = rl.gl;
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
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
    };

fn drawCubeWithTransformMatrix(texture: rl.Texture2D, transform: rl.Matrix, width: f32, height: f32, length: f32, color: rl.Color) void {
    gl.rlSetTexture(texture.id);
    const pos = core.util.transformPosition(transform);
    const x = pos.x;
    const y = pos.y;
    const z = pos.z;
    // Apply the transformation matrix directly
    gl.rlBegin(gl.rl_quads);
    gl.rlColor4ub(color.r, color.g, color.b, color.a);

    const faces_data = [6]struct { normal: [3]f32, coords: [4]struct {
        tex_coords: [2]f32,
        vertex_coords: [3]f32,
    } }{
        // Front Face (+Z)
        .{ .normal = [_]f32{ 0.0, 0.0, 1.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z + length / 2 },
            },
        } },
        // Back Face (-Z)
        .{ .normal = [_]f32{ 0.0, 0.0, -1.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z - length / 2 },
            },
        } },
        // Top Face (+Y)
        .{ .normal = [_]f32{ 0.0, 1.0, 0.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z - length / 2 },
            },
        } },
        // Bottom Face (-Y)
        .{ .normal = [_]f32{ 0.0, -1.0, 0.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z + length / 2 },
            },
        } },
        // Right Face (+X)
        .{ .normal = [_]f32{ 1.0, 0.0, 0.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x + width / 2, y + height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x + width / 2, y - height / 2, z + length / 2 },
            },
        } },
        // Left Face (-X)
        .{ .normal = [_]f32{ -1.0, 0.0, 0.0 }, .coords = .{
            .{
                .tex_coords = [_]f32{ 0.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z - length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 0.0 },
                .vertex_coords = [_]f32{ x - width / 2, y - height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 1.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z + length / 2 },
            },
            .{
                .tex_coords = [_]f32{ 0.0, 1.0 },
                .vertex_coords = [_]f32{ x - width / 2, y + height / 2, z - length / 2 },
            },
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

            const vertex_coords = core.util.transformPosition(rl.Matrix.multiply(translation, transform));

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

// Helper function to apply the transformation matrix to a vertex and render it
fn transformVertex(x: f32, y: f32, z: f32, transform_matrix: rl.Matrix) struct { f32, f32, f32 } {
    const transformed_vertex = transform_matrix.multiply(rl.Matrix.translate(x, y, z));
    const pos = core.util.transformPosition(transformed_vertex);
    return .{ pos.x, pos.y, pos.z };
}
// Draw cube textured
// NOTE: Cube position is the center position
fn drawCubeTexture(texture: rl.Texture2D, position: rl.Vector3, width: f32, height: f32, length: f32, color: rl.Color) void {
    const x = position.x;
    const y = position.y;
    const z = position.z;

    // Set desired texture to be enabled while drawing following vertex data
    gl.rlSetTexture(texture.id);

    // Vertex data transformation can be defined with the commented lines,
    // but in this example we calculate the transformed vertex data directly when calling gl.rlVertex3f()
    //gl.rlPushMatrix();
    // NOTE: Transformation is applied in inverse order (scale -> rotate -> translate)
    //gl.rlTranslatef(2.0, 0.0, 0.0);
    //gl.rlRotatef(45, 0, 1, 0);
    //gl.rlScalef(2.0, 2.0, 2.0);

    gl.rlBegin(gl.rl_quads);
    gl.rlColor4ub(color.r, color.g, color.b, color.a);
    // Front Face
    gl.rlNormal3f(0.0, 0.0, 1.0); // Normal Pointing Towards Viewer
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Top Right Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Left Of The Texture and Quad
    // Back Face
    gl.rlNormal3f(0.0, 0.0, -1.0); // Normal Pointing Away From Viewer
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Bottom Right Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Left Of The Texture and Quad
    // Top Face
    gl.rlNormal3f(0.0, 1.0, 0.0); // Normal Pointing Up
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    // Bottom Face
    gl.rlNormal3f(0.0, -1.0, 0.0); // Normal Pointing Down
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Top Right Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Top Left Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    // Right face
    gl.rlNormal3f(1.0, 0.0, 0.0); // Normal Pointing Right
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2); // Bottom Right Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2); // Top Right Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2); // Top Left Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2); // Bottom Left Of The Texture and Quad
    // Left Face
    gl.rlNormal3f(-1.0, 0.0, 0.0); // Normal Pointing Left
    gl.rlTexCoord2f(0.0, 0.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2); // Bottom Left Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 0.0);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2); // Bottom Right Of The Texture and Quad
    gl.rlTexCoord2f(1.0, 1.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2); // Top Right Of The Texture and Quad
    gl.rlTexCoord2f(0.0, 1.0);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2); // Top Left Of The Texture and Quad
    gl.rlEnd();
    //gl.rlPopMatrix();

    gl.rlSetTexture(0);
}

// Draw cube with texture piece applied to all faces
fn drawCubeTextureRec(texture: rl.Texture2D, source: rl.Rectangle, position: rl.Vector3, width: f32, height: f32, length: f32, color: rl.Color) void {
    const x = position.x;
    const y = position.y;
    const z = position.z;
    const texWidth: f32 = @intCast(texture.width);
    const texHeight: f32 = @intCast(texture.height);

    // Set desired texture to be enabled while drawing following vertex data
    gl.rlSetTexture(texture.id);

    // We calculate the normalized texture coordinates for the desired texture-source-rectangle
    // It means converting from (tex.width, tex.height) coordinates to [0.0, 1.0] equivalent
    gl.rlBegin(gl.rl_quads);
    gl.rlColor4ub(color.r, color.g, color.b, color.a);

    // Front face
    gl.rlNormal3f(0.0, 0.0, 1.0);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2);

    // Back face
    gl.rlNormal3f(0.0, 0.0, -1.0);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2);

    // Top face
    gl.rlNormal3f(0.0, 1.0, 0.0);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2);

    // Bottom face
    gl.rlNormal3f(0.0, -1.0, 0.0);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2);

    // Right face
    gl.rlNormal3f(1.0, 0.0, 0.0);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z - length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z - length / 2);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x + width / 2, y + height / 2, z + length / 2);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x + width / 2, y - height / 2, z + length / 2);

    // Left face
    gl.rlNormal3f(-1.0, 0.0, 0.0);
    gl.rlTexCoord2f(source.x / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z - length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, (source.y + source.height) / texHeight);
    gl.rlVertex3f(x - width / 2, y - height / 2, z + length / 2);
    gl.rlTexCoord2f((source.x + source.width) / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z + length / 2);
    gl.rlTexCoord2f(source.x / texWidth, source.y / texHeight);
    gl.rlVertex3f(x - width / 2, y + height / 2, z - length / 2);

    gl.rlEnd();

    gl.rlSetTexture(0);
}
/// Each die has two "layers"
/// The first is a mesh that is simply the die shape with a certain material
/// The other is a quad for each face that has a number texture on it
pub fn Die(comptime numbers_atlas_path: [:0]const u8) type {
    // std.fs.accessAbsolute(numbers_atlas, .{}) catch {
    //     @compileError("Must pass a valid filepath for numbers_atlas");
    // };

    return struct {
        _type: DieType,
        model: rl.Model,
        quad_texture: rl.Texture2D,
        // faces: rl.Model,
        // quads: [NUM_QUADS]OverlayQuad,

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
            var model = try rl.loadModelFromMesh(mesh);
            model.materials[0] = material;

            return @This(){
                ._type = _type,
                .model = model,
                .quad_texture = quad_tex,
                // .faces = _type.getQuadsMesh(zeroTermAtlasPath()),
            };
        }

        pub fn draw(self: *@This(), world_transform: rl.Matrix) !void {
            const axis, const angle = core.util.transformAxisAngle(world_transform);
            const position =
                core.util.transformPosition(world_transform);
            rl.drawModelEx(self.model, position, axis, angle, rl.Vector3.one(), rl.Color.white);
            // Draw faces
            switch (self._type) {
                .six => drawCubeWithTransformMatrix(self.quad_texture, world_transform, 1.001, 1.001, 1.001, rl.Color.white),
            }
        }
    };
}

pub const OverlayQuad = struct {
    mesh: rl.Mesh,
    // model: rl.Model,
    // texture: rl.Texture2D,
    material: rl.Material,
    // rectangle: rl.Rectangle,
    transform: rl.Matrix,
};

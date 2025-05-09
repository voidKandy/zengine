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
                .six => drawCubeTexture(self.quad_texture, position, 1.001, 1.001, 1.001, rl.Color.white),
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

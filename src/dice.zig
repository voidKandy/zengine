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

/// Each die has two "layers"
/// The first is a mesh that is simply the die shape with a certain material
/// The other is a quad for each face that has a number texture on it
pub fn Die(comptime _type: DieType, comptime numbers_atlas: []const u8) type {
    // std.fs.accessAbsolute(numbers_atlas, .{}) catch {
    //     @compileError("Must pass a valid filepath for numbers_atlas");
    // };

    const NUM_QUADS = switch (_type) {
        .six => 6,
    };

    return struct {
        _type: DieType,
        model: rl.Model,
        quads: [NUM_QUADS]OverlayQuad,

        fn zeroTermAtlasPath() [:0]const u8 {
            var arr: [numbers_atlas.len + 1:0]u8 = undefined;
            @memset(&arr, 0);
            for (&arr, 0..) |*v, i| {
                if (i < numbers_atlas.len) {
                    const byte = numbers_atlas[i];
                    v.* = byte;
                }
            }
            return &arr;
        }

        pub fn new(material: rl.Material, args: anytype) rl.RaylibError!@This() {
            const mesh = try _type.createMeshFunc()(args);
            var model = try rl.loadModelFromMesh(mesh);
            model.materials[0] = material;

            const quad_texture = try rl.loadTexture(zeroTermAtlasPath());
            var quad_material = try rl.loadMaterialDefault();
            quad_material.maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = quad_texture;
            var quads: [NUM_QUADS]OverlayQuad = undefined;
            // CURRENTLY ONLY WORKS FOR A D6
            // Compute UVs for index `i` (0–5)
            const cols = 2;
            const rows = 3;

            const rotations = [_]rl.Matrix{
                rl.Matrix.rotateX(90.0), // Face 1: Top (Rotate 90° around X-axis)
                rl.Matrix.rotateX(-90.0), // Face 2: Bottom (Rotate -90° around X-axis)
                rl.Matrix.rotateY(90.0), // Face 3: Left (Rotate 90° around Y-axis)
                rl.Matrix.rotateY(-90.0), // Face 4: Right (Rotate -90° around Y-axis)
                rl.Matrix.rotateZ(90.0), // Face 5: Front (Rotate 90° around Z-axis)
                rl.Matrix.rotateZ(-90.0), // Face 6: Back (Rotate -90° around Z-axis)
            };

            const positions = [_]rl.Vector3{
                rl.Vector3.init(0.0, 0.5, 0.0), // Position for Face 1 (Top)
                rl.Vector3.init(0.0, -0.5, 0.0), // Position for Face 2 (Bottom)
                rl.Vector3.init(-0.5, 0.0, 0.0), // Position for Face 3 (Left)
                rl.Vector3.init(0.5, 0.0, 0.0), // Position for Face 4 (Right)
                rl.Vector3.init(0.0, 0.0, 0.5), // Position for Face 5 (Front)
                rl.Vector3.init(0.0, 0.0, -0.5), // Position for Face 6 (Back)
            };

            for (&quads, 0..) |*q, i| {
                const rotation = rotations[i];
                const position = positions[i];
                const col = i % cols;
                const row = i / cols;

                const u_min = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols));
                const v_min = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(rows));
                const u_max = (@as(f32, @floatFromInt(col + 1))) / @as(f32, @floatFromInt(cols));
                const v_max = (@as(f32, @floatFromInt(row + 1))) / @as(f32, @floatFromInt(rows));

                // Create a quad mesh
                var plane = rl.genMeshPlane(1.0, 1.0, 1, 1); // Normalized size
                warn(
                    \\ PLANE VERTEX COUNT: {d}
                , .{plane.vertexCount});
                // const texcoords = plane.texcoords[0..@as(usize, @intCast(plane.vertexCount * 2))];

                // Top Left Position in texture
                plane.texcoords[0] = u_min;
                plane.texcoords[1] = v_min;

                // Top Right position in texture
                plane.texcoords[2] = u_max;
                plane.texcoords[3] = v_min;

                // Bottom Right Position in texture
                plane.texcoords[4] = u_max;
                plane.texcoords[5] = v_max;

                // Bottom Left Position in texture
                plane.texcoords[6] = u_min;
                plane.texcoords[7] = v_max;

                warn(
                    \\
                    \\ FACE {}
                    \\ UMIN: {d}
                    \\ UMAX: {d}
                    \\ VMIN: {d}
                    \\ VMAX: {d}
                    \\
                    \\ TOP LEFT: ({d}, {d})
                    \\ TOP RIGHT: ({d}, {d})
                    \\ BOTTOM RIGHT: ({d}, {d})
                    \\ BOTTOM LEFT: ({d}, {d})
                , .{
                    i,                  u_min,              v_min,              u_max,              v_max,
                    plane.texcoords[0], plane.texcoords[1], plane.texcoords[2], plane.texcoords[3], plane.texcoords[4],
                    plane.texcoords[5], plane.texcoords[6], plane.texcoords[7],
                });

                const transform = trans: {
                    var t =
                        rl.Matrix.identity();
                    t = t.multiply(rotation);
                    t = t.multiply(rl.Matrix.translate(position.x, position.y, position.z));
                    break :trans t;
                };

                q.* = OverlayQuad{
                    .mesh = plane,
                    .material = quad_material,
                    .transform = transform,
                };
            }

            return @This(){
                ._type = _type,
                .model = model,
                .quads = quads,
                // .mesh = mesh,
                // .material = material,
            };
        }

        pub fn draw(self: *@This(), position: rl.Vector3) !void {
            rl.drawModel(self.model, position, 1.0, rl.Color.white);

            for (&self.quads) |*quad| {
                try quad.draw(position, 1.0);
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

    fn draw(self: *@This(), base_pos: rl.Vector3, base_scale: f32) rl.RaylibError!void {
        _ = base_pos;
        _ = base_scale;
        // var material = try rl.loadMaterialDefault();
        // material.maps[0].texture = self.texture;

        rl.drawMesh(self.mesh, self.material, self.transform);
        // self.texture.drawRec(source: Rectangle, position: Vector2, tint: Color)
        // rl.drawModelEx(
        //     self.model,
        //     base_pos,
        //     .{ 0, 0, 0 },
        //     0,
        //     rl.Vector3.init(base_scale, base_scale, base_scale),
        //     rl.Color.white,
        // );
    }
};

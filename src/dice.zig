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

            const numbers_atlas_img = try rl.loadImage(zeroTermAtlasPath());

            var quads: [NUM_QUADS]OverlayQuad = undefined;
            // CURRENTLY ONLY WORKS FOR A D6
            // Compute UVs for index `i` (0–5)
            const cols = 2;
            // const rows = 3;

            const deg2rad = std.math.pi / 180.0;
            const rotations_and_positions = [_]struct { rl.Matrix, rl.Vector3 }{
                // TOP
                .{
                    rl.Matrix.identity(),
                    rl.Vector3.init(0.0, 0.5, 0.0),
                },
                // BOTTOM
                .{
                    rl.Matrix.rotateX(180.0 * deg2rad),
                    rl.Vector3.init(0.0, -0.5, 0.0),
                },
                // RIGHT
                .{
                    rl.Matrix.rotateXYZ(rl.Vector3.init(90.0 * deg2rad, 0.0, -90.0 * deg2rad)),
                    rl.Vector3.init(0.5, 0.0, 0.0),
                },
                // LEFT
                .{
                    rl.Matrix.rotateXYZ(rl.Vector3.init(90.0 * deg2rad, 0.0, 90.0 * deg2rad)),
                    rl.Vector3.init(-0.5, 0.0, 0.0),
                },
                // FRONT
                .{
                    rl.Matrix.rotateX(90.0 * deg2rad),
                    rl.Vector3.init(0.0, 0.0, 0.5),
                },
                // BACK
                .{
                    rl.Matrix.rotateX(180.0 * deg2rad),
                    rl.Vector3.init(0.0, 0.0, -0.5),
                },
            };

            for (&quads, 0..) |*q, i| {
                const rotation, const position = rotations_and_positions[i];
                const col = i % cols;
                const row = i / cols;

                // const u_min = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols));
                // const v_min = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(rows));
                // const u_max = (@as(f32, @floatFromInt(col + 1))) / @as(f32, @floatFromInt(cols));
                // const v_max = (@as(f32, @floatFromInt(row + 1))) / @as(f32, @floatFromInt(rows));

                const rect = rl.Rectangle{
                    .x = @as(f32, @floatFromInt(col)) * 256.0,
                    .y = @as(f32, @floatFromInt(row)) * 256.0,
                    .width = 256.0,
                    .height = 256.0,
                };
                // const rect =
                //     rl.Rectangle{ .x = u_min, .y = v_min, .width = 256.0, .height = 256.0 };
                warn(
                    \\ CROPPING IMAGE WITH RECTANGLE: {any}
                , .{rect});
                const quad_img = numbers_atlas_img.copyRec(rect);
                const quad_tex = try rl.loadTextureFromImage(quad_img);
                var quad_material = try rl.loadMaterialDefault();
                quad_material.maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].texture = quad_tex;
                quad_material.maps[@intFromEnum(rl.MATERIAL_MAP_DIFFUSE)].color = switch (i) {
                    0 => rl.Color.blue,
                    1 => rl.Color.orange,
                    2 => rl.Color.red,
                    3 => rl.Color.green,
                    4 => rl.Color.pink,
                    5 => rl.Color.yellow,
                    else => rl.Color.white,
                };

                // Create a quad mesh
                const plane = rl.genMeshPlane(1.0, 1.0, 256, 256); // Normalized size

                const transform = trans: {
                    var t =
                        rl.Matrix.identity();
                    t = t.multiply(rotation);
                    t = t.multiply(rl.Matrix.translate(position.x, position.y, position.z));
                    break :trans t;
                };
                // _ = position;

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
                // var model = try rl.loadModelFromMesh(quad.mesh);
                // model.materials[0] = quad.material;
                // model.draw(position, 1.0, rl.Color.white);

                // try quad.draw(position, 1.0);
                rl.drawMesh(quad.mesh, quad.material, quad.transform);
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

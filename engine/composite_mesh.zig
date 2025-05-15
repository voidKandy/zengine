const rl = @import("raylib");
const zbt = @import("zbullet");

const CompositeMeshElement = struct {
    mesh: rl.Mesh,
    shape: zbt.Shape,
    transform: rl.Matrix,
};
// fn CompositeMesh(elements: []const CompositeMeshElement) struct {zbt.CompoundShape, rl.Matrix} {

//     zbt.initCompoundShape(.{}).addChild(local_transform: *const [12]f32, child_shape: Shape)
// }

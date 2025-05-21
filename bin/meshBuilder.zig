const std = @import("std");
const engine_core = @import("engine_core");
const rl = @import("raylib");
const zbt = @import("zbullet");

/// Because materials require a window context, this test needed to be a binary rather than
/// a test
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer {
        arena.deinit();
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) std.testing.expect(false) catch @panic("FAIL");
    }

    std.debug.print(
        \\ Mesh Bundle Test
        \\
    , .{});
    rl.setConfigFlags(.{ .window_hidden = true });
    rl.initWindow(800, 600, "Test Window");

    defer rl.closeWindow();
    const default_material = try rl.loadMaterialDefault();
    var bundle = engine_core.MeshBundle.init(arena.allocator(), &[_]rl.Material{ default_material, mat: {
        var m = try rl.loadMaterialDefault();
        m.maps[0].color = rl.Color.red;
        break :mat m;
    } });
    const mesh = rl.genMeshCube(1.0, 1.0, 1.0);
    try bundle.add(mesh, 0);
    const other_mesh = rl.genMeshCube(1.0, 1.0, 1.0);
    try bundle.add(other_mesh, 1);

    defer bundle.deinit();
}

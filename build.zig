const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // External Dependencies
    // ---
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");
    const zbullet = b.dependency("zbullet", .{});
    const zmath = b.dependency("zmath", .{});

    // Engine Library
    // ---
    const engine_core_lib = b.addModule("engine_core", .{
        .root_source_file = b.path("engine/root.zig"),
    });
    engine_core_lib.addImport("zbullet", zbullet.module("root"));
    engine_core_lib.addImport("zmath", zmath.module("root"));
    engine_core_lib.linkLibrary(zbullet.artifact("cbullet"));
    engine_core_lib.linkLibrary(raylib_artifact);
    engine_core_lib.addImport("raylib", raylib);
    engine_core_lib.addImport("raygui", raygui);

    const engine_unit_tests = b.addTest(.{
        .root_source_file = b.path("engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // lib_unit_tests.root_module.addImport("engine_core", engine_core_lib);
    engine_unit_tests.root_module.addImport("zbullet", zbullet.module("root"));
    engine_unit_tests.linkLibrary(zbullet.artifact("cbullet"));
    engine_unit_tests.linkLibrary(raylib_artifact);
    engine_unit_tests.root_module.addImport("raylib", raylib);
    engine_unit_tests.root_module.addImport("zmath", zmath.module("root"));
    engine_unit_tests.root_module.addImport("raygui", raygui);

    const run_engine_unit_tests = b.addRunArtifact(engine_unit_tests);

    const engine_test_step = b.step("test_engine", "Run unit tests");
    engine_test_step.dependOn(&run_engine_unit_tests.step);

    // Game Library
    // ---
    const game_core_lib = b.addModule("game_core", .{
        .root_source_file = b.path("game/root.zig"),
    });
    game_core_lib.addImport("engine_core", engine_core_lib);
    game_core_lib.addImport("zbullet", zbullet.module("root"));
    game_core_lib.addImport("zmath", zmath.module("root"));
    game_core_lib.linkLibrary(zbullet.artifact("cbullet"));
    game_core_lib.linkLibrary(raylib_artifact);
    game_core_lib.addImport("raylib", raylib);
    game_core_lib.addImport("raygui", raygui);

    const game_unit_tests = b.addTest(.{
        .root_source_file = b.path("game/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    game_unit_tests.root_module.addImport("engine_core", engine_core_lib);
    game_unit_tests.root_module.addImport("zbullet", zbullet.module("root"));
    game_unit_tests.linkLibrary(zbullet.artifact("cbullet"));
    game_unit_tests.linkLibrary(raylib_artifact);
    game_unit_tests.root_module.addImport("raylib", raylib);
    game_unit_tests.root_module.addImport("zmath", zmath.module("root"));
    game_unit_tests.root_module.addImport("raygui", raygui);

    const run_game_unit_tests = b.addRunArtifact(game_unit_tests);

    const game_test_step = b.step("test_game", "Run unit tests");
    game_test_step.dependOn(&run_game_unit_tests.step);

    // Binaries
    // ---
    //
    const bins_entry = b.path("bin/all.zig");
    const bins_dir = "bin";
    const dir = std.fs.cwd().openDir(bins_dir, .{}) catch |e| std.debug.panic("Failed to get directory {s}: {}\n", .{ bins_entry.src_path.sub_path, e });
    var buffer: [256]u8 = undefined;
    @memset(&buffer, 0);
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var iter = dir.iterate();
    while (iter.next() catch |e| std.debug.panic("Dir iterator failure: {}\n", .{e})) |f| {
        const name = name: {
            var split = std.mem.splitBackwardsScalar(u8, f.name, '.');
            _ = split.first();
            break :name split.next() orelse @panic("malformed test file name");
        };

        const fullpath = std.fmt.allocPrint(fba.allocator(), "{s}/{s}", .{ bins_dir, f.name }) catch |e| std.debug.panic("Failed to get full path: {}\n", .{e});
        const exe = b.addExecutable(.{ .name = name, .root_source_file = b.path(fullpath), .target = target, .optimize = optimize });

        exe.root_module.addImport("engine_core", engine_core_lib);
        exe.root_module.addImport("game_core", game_core_lib);
        exe.root_module.addImport("zbullet", zbullet.module("root"));
        exe.linkLibrary(zbullet.artifact("cbullet"));
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("zmath", zmath.module("root"));
        exe.root_module.addImport("raylib", raylib);
        exe.root_module.addImport("raygui", raygui);

        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        const step = b.step(name, f.name);
        step.dependOn(&run.step);

        if (b.args) |args| {
            run.addArgs(args);
        }

        // const run = b.addRunArtifact(exe);
        // const step = b.step(step_name, f.name);
        // exe.dependOn(&run);
    }
}

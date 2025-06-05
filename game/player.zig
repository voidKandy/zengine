const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("engine_core");
const zm = @import("zmath");

pub const PlayerInteract = enum {
    pickup,
    push,

    const SIZE = @typeInfo(PlayerInteract).@"enum".fields.len;
    pub const Signature = std.bit_set.IntegerBitSet(SIZE);

    pub inline fn signature(kinds: []const PlayerInteract) Signature {
        var new = Signature.initEmpty();
        for (kinds) |k| {
            new.set(@intFromEnum(k));
        }
        return new;
    }
};

//     fn sync(entities: []core.ecs.Entity, myecs: *Ecs, state: *core.state.State) void {}
// }.sync);

test {
    std.debug.print(
        \\ Player
        \\
    , .{});
}

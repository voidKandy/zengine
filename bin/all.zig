const std = @import("std");

pub fn main() void {
    std.debug.print("Hello from All bins!\n", .{});
}

test {
    // const std = @import("std");
    _ = @import("game.zig");
    std.testing.refAllDecls(@This());
}

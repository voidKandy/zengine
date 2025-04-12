const std = @import("std");
pub fn DynamicArray(comptime T: type, comptime InitSize: usize) type {
    const Error = error{
        Capacity,
    };
    return struct {
        items: [InitSize]?T,
        amt: usize,
        const Self = @This();

        fn all_items(self: Self) []const T {
            var split = std.mem.splitScalar(?T, self.items, null);
            return split.first();
        }

        const IncreasedScale =
            DynamicArray(T, InitSize * 2);

        const DecreasedScale = DynamicArray(T, InitSize / 2);

        pub fn init() Self {
            std.log.debug("INITILIAZING DYNAMIC ARRAY OF SIZE: {}\n", .{InitSize});
            var my_items: [InitSize]?T = undefined;
            @memset(&my_items, null);
            return .{ .items = my_items, .amt = 0 };
        }

        pub fn from(items: []const T) Error!Self {
            var new = Self.init();
            for (items) |i| {
                try new.push(i);
            }
            return new;
        }

        pub fn pop(self: *Self) ?T {
            if (self.amt > 0) {
                const item = self.items[self.amt - 1] orelse @panic("Got no item where one was expected");
                self.amt -= 1;
                return item;
            }

            return null;
        }

        pub fn push(self: *Self, item: T) Error!void {
            if (self.amt >= InitSize)
                return Error.Capacity;
            self.items[self.amt] = item;
            self.amt += 1;
        }

        pub fn push_resize(self: *Self, item: T) Error!void {
            if (self.amt >= InitSize) {
                var new = try self.resize_increase();
                new.push(item) catch @panic("should not fail to push to a resized array");
                return;
            }
            self.items[self.amt] = item;
            self.amt += 1;
        }

        fn resize_increase(self: Self) Error!IncreasedScale {
            var new =
                IncreasedScale.init();
            for (0..self.amt) |i| {
                if (self.items[i]) |item| {
                    try new.push(item);
                } else {
                    break;
                }
            }
            return new;
        }
        fn resize_decrease(self: Self) Error!DecreasedScale {
            var new =
                DecreasedScale.init();
            for (0..self.amt) |i| {
                if (self.items[i]) |item| {
                    new.push(item);
                } else {
                    break;
                }
            }
            return new;
        }
    };
}

test "dynamic init push/pop" {
    var dynamic = DynamicArray(u8, 8).init();

    for ([_]u8{
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
    }) |i| {
        try dynamic.push(i);
    }

    var new = try dynamic.resize_increase();
    new.push(8) catch @panic("Failed to push 8 ");

    try std.testing.expectEqual(new.pop().?, 8);
    try std.testing.expectEqual(new.pop().?, 7);
    try std.testing.expectEqual(new.pop().?, 6);
    try std.testing.expectEqual(new.pop().?, 5);
}

test "dynamic push resize" {
    var dynamic = DynamicArray(u8, 8).init();

    for ([_]u8{
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
    }) |i| {
        try dynamic.push(i);
    }

    dynamic.push_resize(8) catch @panic("Failed to push 8 ");
}

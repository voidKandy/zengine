const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
const warn = std.log.warn;
const Type = std.builtin.Type;
const Shape = zbt.Shape;
const Allocator = std.mem.Allocator;

/// Used to manage any struct that can be identified with a `u32` and that has a signature
/// (Entities & Systems)
fn IdentifierManager(
    MAX: comptime_int,
    SIGNATURE_SIZE: comptime_int,
) type {
    return struct {
        const Identifier = u32;
        const Signature = std.bit_set.IntegerBitSet(@intCast(SIGNATURE_SIZE));
        const IdQueue = std.DoublyLinkedList(Identifier);
        const Self = @This();
        const Error = error{
            NoIdentifier,
            Insert,
            NoIndex,
            Random,
            OutOfMemory,
        };

        available_ids: *IdQueue.Node,
        index_map: std.AutoHashMap(Identifier, usize),
        identifier_map: std.AutoHashMap(usize, Identifier),
        count: usize,
        signatures: [MAX]Signature = initsigs: {
            var signatures: [MAX]Signature = undefined;
            @memset(&signatures, Signature.initEmpty());
            break :initsigs signatures;
        },

        /// requires the same allocator be passed as with `init`
        fn deinit(self: *@This(), allocator: Allocator) void {
            defer self.index_map.deinit();
            defer self.identifier_map.deinit();
            var current = self.available_ids;
            while (current.next) |n| {
                allocator.destroy(current);
                current = n;
            }
            allocator.destroy(current);
        }

        fn init(allocator: Allocator) Error!Self {
            var prng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch return error.Random;
                break :blk seed;
            });
            const rand = prng.random();

            const head = allocator.create(IdQueue.Node) catch return error.OutOfMemory;
            head.* = IdQueue.Node{ .next = null, .data = rand.int(u32) };
            var current = head;
            for (0..MAX) |_| {
                const id = rand.int(u32);
                // warn("Added ID: {} to queue\n", .{id});
                const node = allocator.create(IdQueue.Node) catch |e| {
                    std.log.err("Error: {}", .{e});
                    return error.OutOfMemory;
                };
                node.* = IdQueue.Node{ .next = null, .data = id };
                current.next = node;
                current = node;
            }

            const idx_map = std.AutoHashMap(Identifier, usize).init(allocator);
            const ent_map = std.AutoHashMap(usize, Identifier).init(allocator);
            return Self{
                .available_ids = head,
                .index_map = idx_map,
                .identifier_map = ent_map,
                .count = 0,
            };
        }

        /// Returns a tuple of the `Identifier` (`u32`) and the index
        fn register(
            self: *Self,
        ) Error!struct { Identifier, usize } {
            defer {
                warn(
                    \\ NEW COUNT: {}
                    \\ ARRAY: 
                , .{
                    // sig.mask,
                    self.count});
                // inline for (self.signatures) |s| {
                //     warn("{b}", .{s.mask});
                // }
            }

            const id: Identifier = ent: {
                const node = self.available_ids;
                const next = self.available_ids.next orelse return error.NoIdentifier;
                self.available_ids = next;
                break :ent node.data;
            };
            warn(
                \\ REGISTERING IDENTIFIER: {}
                \\ COUNT: {}
            , .{ id, self.count });
            self.index_map.put(id, self.count) catch return error.Insert;
            self.identifier_map.put(self.count, id) catch return error.Insert;
            // self.signatures[self.count] = Signature.initEmpty();
            self.count += 1;

            return .{ id, self.count - 1 };
        }

        fn lastRegistered(self: Self) ?struct { Identifier, usize } {
            const idx = self.count - 1;
            const id = self.identifier_map.get(idx) orelse return null;
            return .{ id, idx };
        }

        /// Allocates Queue node for the removed entity
        fn remove(self: *Self, allocator: Allocator, id: Identifier) Error!void {
            const index = self.index_map.get(id) orelse return error.NoIndex;

            warn(
                \\
                \\ REMOVING ID: {}
                \\ IDX: {}
            , .{
                id, index,
            });

            if (self.lastRegistered()) |last_reg| {
                if (last_reg.@"0" != id) {
                    const last_sig = self.getSignature(last_reg.@"0") orelse @panic("No signature for last inserted?");
                    warn(
                        \\
                        \\ LAST REGISTERED EXISTS
                        \\ ID: {}
                        \\ IDX: {}
                        \\ SIG: {b}
                    , .{
                        last_reg.@"0",
                        last_reg.@"1",
                        last_sig.mask,
                    });
                    self.index_map.put(last_reg.@"0", index) catch return error.Insert;
                    self.identifier_map.put(index, last_reg.@"0") catch return error.Insert;
                    self.signatures[index] = last_sig;
                    self.signatures[last_reg.@"1"] = Signature.initEmpty();
                }
            }
            // const last_sig = self.signatures[self.count - 1];
            // const last_ent = self.identifier_map.get(self.count - 1) orelse return error.NoIdentifier;

            const node = allocator.create(IdQueue.Node) catch return error.OutOfMemory;
            node.* = IdQueue.Node{ .next = null, .data = id };
            var current: *IdQueue.Node = self.available_ids.next orelse @panic("EMPTY IDS?");
            while (current.next) |next| {
                current = next;
            }
            current.next = node;
            self.count -= 1;
            std.log.debug(
                \\ NEW COUNT: {}
            , .{self.count});
            return;
        }

        /// Gets all entities who have at least all the bits that are set in the given signature set
        fn getBySignatureAtLeast(self: Self, buffer: *[MAX]Identifier, signature: Self.Signature) ?[]Identifier {
            var amt: usize = 0;
            for (0.., self.signatures) |i, sig| {
                if (signature.subsetOf(sig)) {
                    const identifier = self.identifier_map.get(i) orelse @panic("NO MATCHING IDENTIFIER FOR THAT INDEX");
                    // std.log.debug("Entity at index {} has a matching signature\nID: {}\n", .{ i, identifier });
                    buffer[amt] = identifier;
                    amt += 1;
                }
            }

            if (amt < 1) {
                return null;
            }

            return buffer[0..amt];
        }

        /// Gets all entities that match the given signature *exactly*
        fn getBySignatureExact(self: Self, buffer: *[MAX]Identifier, signature: Self.Signature) ?[]Identifier {
            // var all: [MAX]Identifier = undefined;
            // @memset(&all, 0);
            var amt: usize = 0;
            for (0.., self.signatures) |i, sig| {
                if (signature.eql(sig)) {
                    const identifier = self.identifier_map.get(i) orelse @panic("NO MATCHING IDENTIFIER FOR THAT INDEX");
                    std.log.warn("Entity at index {} has a matching signature\nID: {}\n", .{ i, identifier });
                    buffer[amt] = identifier;
                    amt += 1;
                }
                // std.log.warn("ALL: {any}\n", .{all});
            }

            if (amt < 1) {
                return null;
            }
            const ret =
                buffer[0..amt];

            std.log.warn("RET: {any}\n", .{ret});
            return ret;
        }

        fn getSignature(self: Self, entity: Identifier) ?Self.Signature {
            const idx = self.index_map.get(entity) orelse return null;
            return self.signatures[idx];
        }
        // fn register_component_for_entity(self: *Self, entity: Identifier, component: anytype) void {}
    };
}

pub const Component = struct { [:0]const u8, type };
pub const Entity = u32;

/// Entity Component System "Coordinator"
pub fn Ecs(
    MaxNEntities: comptime_int,
    MaxNSystems: comptime_int,
    comptime State: type,
    comptime Components: []const Component,
) type {
    if (MaxNEntities == 0 or MaxNSystems == 0) {
        @compileError("Set MaxNEntities & MaxNSystems to at least 1!");
    }
    return struct {
        const ThisEcs = @This();
        pub const Signature = std.bit_set.IntegerBitSet(@intCast(Components.len));
        pub const ComponentsEnum = ComponentsManager.Enum;

        /// Returns the signature associated with the given components
        pub fn get_signature(components: []ComponentsEnum) Signature {
            var sig = Signature.initEmpty();
            for (components) |c| {
                sig.set(@intFromEnum(c));
            }
            return sig;
        }

        const ComponentsManager = cmp_man: {
            const N = Components.len;
            const ComponentTag: type, const TypeArr: [N]type = blk: {
                var fields: [N]Type.EnumField = undefined;
                var types: [N]type = undefined;
                @memset(&fields, Type.EnumField{
                    .name = "",
                    .value = 0,
                });

                for (0.., Components, &types) |i, c, *t| {
                    fields[i] = Type.EnumField{
                        .name = c.@"0",
                        .value = i,
                    };
                    t.* = c.@"1";
                }

                break :blk .{ @Type(Type{ .@"enum" = .{
                    .tag_type = u32,
                    .fields = &fields,
                    .decls = &[_]Type.Declaration{},
                    .is_exhaustive = true,
                } }), types };
            };

            break :cmp_man struct {
                const Enum = ComponentTag;
                /// Each array corresponds with the components in the order they were passed
                arrays: [N][MaxNEntities]?*anyopaque,
                const Error = error{ InvalidType, OutOfMemory };
                inline fn tagType(which: Enum) type {
                    return TypeArr[@intFromEnum(which)];
                }

                pub fn init() @This() {
                    return @This(){ .arrays = arr: {
                        var arr: [N][MaxNEntities]?*anyopaque = undefined;
                        @memset(&arr, inner: {
                            var a: [MaxNEntities]?*anyopaque = undefined;
                            @memset(&a, null);
                            break :inner a;
                        });
                        break :arr arr;
                    } };
                }

                /// **Must** be called with allocator used to insert values
                pub fn deinit(
                    self: @This(),
                    allocator: Allocator,
                ) void {
                    inline for (self.arrays, 0..) |subarr, i| {
                        for (subarr) |opt| {
                            if (opt) |v| {
                                const typed = @as(*TypeArr[i], @alignCast(@ptrCast(v)));
                                allocator.destroy(typed);
                            }
                        }
                    }
                }

                /// expects to be passed `*T` for `component`
                /// **NEVER** use multiple allocators for a single instance
                pub fn insert(self: *@This(), allocator: Allocator, which: Enum, idx: usize, component: anytype) Error!void {
                    inline for (TypeArr, 0..) |T, i| {
                        if (i == @intFromEnum(which) and @TypeOf(component.*) == T) {
                            const val_ptr = try allocator.create(T);
                            val_ptr.* = component.*;
                            self.arrays[@intFromEnum(which)][idx] = val_ptr;
                            return;
                        }
                    }
                    return error.InvalidType;
                }

                /// moves component at `idx` to `to_idx`
                /// Nullifies data that was previously at `to_idx`
                fn swap(self: *@This(), which: Enum, idx: usize, to_idx: usize) void {
                    var arr = self.arrays[@intFromEnum(which)];
                    const tmp = arr[idx];
                    arr[to_idx] = tmp;
                    arr[idx] = null;
                    self.arrays[@intFromEnum(which)] = arr;
                }

                pub fn removeNoReturn(self: *@This(), which: Enum, idx: usize) void {
                    self.arrays[@intFromEnum(which)][idx] = null;
                    return;
                }

                pub fn removeWithReturn(self: *@This(), T: type, which: Enum, idx: usize) ?*T {
                    const val = self.arrays[@intFromEnum(which)][idx];
                    self.removeNoReturn(which, idx);
                    return @alignCast(@ptrCast(val));
                }

                pub fn access(self: *@This(), T: type, which: Enum, idx: usize) ?*T {
                    std.log.warn("ACCESSING ARRAY: {any}\n", .{self.arrays[@intFromEnum(which)]});
                    const ptr = self.arrays[@intFromEnum(which)][idx] orelse return null;
                    if (@intFromPtr(ptr) % @alignOf(T) != 0) {
                        @panic("Misaligned pointer access in ECS component store");
                    }
                    return @alignCast(@ptrCast(ptr));
                }
            };
        };

        const EntityManager = struct {
            manager: IdentifierManager(MaxNEntities, Components.len),

            fn init(allocator: Allocator) @This() {
                return .{ .manager = IdentifierManager(MaxNEntities, Components.len).init(allocator) catch @panic("Could not create IdentifierManager for Entities") };
            }

            fn register(self: *@This()) !EntityHandle {
                const id, const i = try self.manager.register();
                _ = i;
                var parent_ptr =
                    @as(*ThisEcs, @fieldParentPtr("entities", self));
                _ = &parent_ptr;

                return EntityHandle{
                    .ecs = parent_ptr,
                    .identifier = id,
                    // .index = i,
                };
            }
            /// I dont think I like having this behavior like this
            /// Not because it's BAD, but because it presents inconsitencies
            pub const EntityHandle = struct {
                ecs: *ThisEcs,
                identifier: Entity,

                /// Is `null` if the entity has been removed
                /// This is a little weird, I feel like the handle should be invalidated if index doesn't exist somehow
                /// In other words, a state where this returns `null` should ideally be impossible
                pub fn index(self: @This()) ?usize {
                    return self.ecs.entities.manager.index_map.get(self.identifier);
                }

                /// Maybe not the best name?
                /// Removes this entity from the ecs
                /// moves component data to match up indices of the outer components array with the index of the entity
                pub fn destroy(self: @This()) !void {
                    const idx = self.index() orelse return error.NoIndex;
                    // Before removing the entity, we clear it's component data
                    {
                        const sig = self.ecs.entities.manager.getSignature(self.identifier) orelse @panic("No entity signature?");
                        var bit_idx_iter = sig.iterator(.{});
                        while (bit_idx_iter.next()) |i| {
                            const comp_enum: ComponentsEnum = @enumFromInt(i);
                            self.ecs.components.removeNoReturn(comp_enum, idx);
                        }
                    }

                    const last_registered_opt = self.ecs.entities.manager.lastRegistered();

                    try self.ecs.entities.manager.remove(self.ecs.allocator, self.identifier);

                    // Removing the entity will move the last inserted entity
                    // We need to update the component data for this moved entity
                    {
                        if (last_registered_opt) |last| {
                            const prev_idx_of_moved_ent = last.@"1";
                            // NOTE:
                            // The index we pass here is the *same* index of the removed entity
                            // because the `remove` method moves the last inserted entity into the index of the removed entity
                            const ent = self.ecs.entities.manager.identifier_map.get(idx) orelse @panic("No identifier at that index?");
                            if (last.@"0" != ent) {
                                std.debug.panic(
                                    \\ Expected last entity inserted to match gotten entity
                                    \\ Expected: {}
                                    \\ Got: {}
                                , .{ last.@"0", ent });
                            }
                            const sig = self.ecs.entities.manager.getSignature(ent) orelse @panic("No entity signature?");
                            var bit_idx_iter = sig.iterator(.{});
                            while (bit_idx_iter.next()) |i| {
                                const comp_enum: ComponentsEnum = @enumFromInt(i);
                                self.ecs.components.swap(comp_enum, prev_idx_of_moved_ent, idx);
                            }
                        }
                    }
                }

                pub fn removeComponent(self: *@This(), which: ComponentsEnum, component: anytype) !void {
                    const idx = self.index() orelse @panic("NO INDEX?");
                    var sig = self.ecs.entities.manager.signatures[idx];
                    sig.unset(@intFromEnum(which));
                    self.ecs.components.removeWithReturn(@TypeOf(component), which, idx) orelse return error.ComponentRemovalFailure;
                }

                pub fn addComponent(self: *@This(), which: ComponentsEnum, component: anytype) !void {
                    const idx = self.index() orelse @panic("NO INDEX?");
                    // const signature = self.ecs.get_signature(&[_]ComponentsEnum{component});
                    var sig = self.ecs.entities.manager.signatures[idx];
                    std.log.debug("sig: {b}\n", .{sig.mask});
                    sig.set(@intFromEnum(which));
                    std.log.debug("changed sig: {b}\n", .{sig.mask});
                    self.ecs.entities.manager.signatures[idx] = sig;
                    try self.ecs.components.insert(self.ecs.allocator, which, idx, component);
                }
            };
        };

        const SystemFn = *const fn ([]Entity, *ThisEcs, *State) void;

        pub fn System(
            components: []const ComponentsEnum,
            _func: SystemFn,
        ) type {
            return struct {
                func: SystemFn = _func,
                signature: Signature = sig: {
                    var s = Signature.initEmpty();
                    for (components) |c| {
                        s.set(@intFromEnum(c));
                    }
                    break :sig s;
                },
            };
        }
        const SystemManager = struct {
            const MyManager = IdentifierManager(MaxNSystems, Components.len);
            manager: MyManager,
            all_fns: [MaxNSystems]?SystemFn = a: {
                var a: [MaxNSystems]?SystemFn = undefined;
                @memset(&a, null);
                break :a a;
            },

            fn init(allocator: Allocator) @This() {
                return .{ .manager = IdentifierManager(MaxNSystems, Components.len).init(allocator) catch @panic("Failed to crate id manager for systems") };
            }
            fn register(self: *@This(), system: anytype) !void {
                const system_id, const system_idx = try self.manager.register();
                std.log.warn("REGISTERED SYSTEM WITH ID: {} INTO ECS", .{system_id});
                self.manager.signatures[system_idx] = system.signature;
                self.all_fns[system_idx] = system.func;
            }

            /// The same kind of thing as `EntityHandle.destroy`
            /// removes the system and then move the function of the moved system to the old index of the removed system
            fn remove(self: *@This(), allocator: Allocator, system_id: MyManager.Identifier) !void {
                const idx = self.manager.index_map.get(system_id) orelse return error.NoSystem;
                try self.manager.remove(allocator, system_id);
                if (self.manager.lastRegistered()) |last| {
                    const fn_to_move = self.all_fns[last.@"1"];
                    self.all_fns[idx] = fn_to_move;
                    self.all_fns[last.@"1"] = null;
                }
            }
        };

        /// this is an allocator returned by `ArenaAllocator.allocator()`
        allocator: Allocator,
        entities: EntityManager,
        systems: SystemManager,
        components: ComponentsManager,

        pub fn init(arena: *std.heap.ArenaAllocator) ThisEcs {
            const alloc = arena.allocator();
            return ThisEcs{
                .allocator = alloc,
                .entities = EntityManager.init(alloc),
                .systems = SystemManager.init(alloc),
                .components = ComponentsManager.init(),
            };
        }

        pub fn deinit(self: *ThisEcs) void {
            self.entities.manager.deinit(self.allocator);
            self.systems.manager.deinit(self.allocator);
            self.components.deinit(self.allocator);
        }

        pub fn runSystems(self: *ThisEcs, state: *State) !void {
            var iter =
                self.systems.manager.identifier_map.iterator();
            while (iter.next()) |e| {
                const id = e.value_ptr;
                const idx = e.key_ptr;
                std.log.warn("RUNNING SYSTEM: {}\n", .{id.*});

                const sig = self.systems.manager.getSignature(id.*) orelse return error.NoSignature;
                var all: [MaxNEntities]Entity = undefined;
                @memset(&all, 0);
                if (self.entities.manager.getBySignatureAtLeast(&all, sig)) |entities| {
                    const func = self.systems.all_fns[idx.*] orelse return error.NoFunction;
                    func(entities, self, state);
                }
            }
        }
    };
}

test "ECS Entity Management" {
    std.testing.refAllDecls(@This());
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print(
        \\
        \\ ---INIT ECS TEST---
        \\
    , .{});

    const State = struct {};
    const MyEcs = Ecs(5, 5, State, &[_]Component{
        .{ "somecomponent", bool },
        .{ "othercomponent", u8 },
        .{ "someothercomponent", u32 },
    });

    var ecs = MyEcs.init(&arena);
    defer ecs.deinit();

    // Entity Initialization
    // ---
    const entity_a: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        var someother: u32 = 5;
        try handle.addComponent(MyEcs.ComponentsEnum.someothercomponent, &someother);
        var some: bool = false;
        try handle.addComponent(MyEcs.ComponentsEnum.somecomponent, &some);
        break :a handle;
    };

    const entity_b: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        var someother: u32 = 7;
        try handle.addComponent(MyEcs.ComponentsEnum.someothercomponent, &someother);
        var some: bool = true;
        try handle.addComponent(MyEcs.ComponentsEnum.somecomponent, &some);
        break :a handle;
    };

    var entity_c: MyEcs.EntityManager.EntityHandle = a: {
        const handle = try ecs.entities.register();
        break :a handle;
    };

    // Entity Component Validation
    // ---
    {
        const got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, 5);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, false);
    }
    {
        const got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_b.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, 7);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_b.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, true);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_c.index().?);
        try std.testing.expect(got == null);
    }

    var all: [5]Entity = undefined;
    @memset(&all, 0);

    const matching = ecs.entities.manager.getBySignatureExact(&all, s: {
        var s = MyEcs.Signature.initEmpty();
        s.set(@intFromEnum(MyEcs.ComponentsEnum.somecomponent));
        s.set(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
        break :s s;
    }) orelse @panic("should have got some matching entities");

    std.log.debug("got matching: {any}\n", .{matching});
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_a.identifier));
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_b.identifier));

    // Component Removal
    // ---

    {
        const removed = ecs.components.removeWithReturn(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.index().?) orelse @panic("nothing at that index");
        try std.testing.expectEqual(removed.*, false);
        try std.testing.expectEqual(null, ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.index().?));
    }

    // Entity Index Storage
    // ---
    {
        try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_a.identifier));
        try std.testing.expectEqual(1, ecs.entities.manager.index_map.get(entity_b.identifier));
        try std.testing.expectEqual(2, ecs.entities.manager.index_map.get(entity_c.identifier));

        // adding component to `entity_c` to make sure the component data is moved as expected
        var val: u8 = 64;
        try entity_c.addComponent(.othercomponent, &val);

        try entity_a.destroy();
        try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_c.identifier));
        try std.testing.expectEqual(0, entity_c.index().?);

        const got = ecs.components.access(u8, .othercomponent, entity_c.index().?);
        try std.testing.expectEqual(val, got.?.*);
    }
    // Systems
    // ---
    const SomeSystem = MyEcs.System(&[_]MyEcs.ComponentsEnum{.someothercomponent}, struct {
        fn run(entities: []Entity, myecs: *MyEcs, state: *State) void {
            _ = state;
            warn("IN SOME SYSTEM\n", .{});
            for (entities) |e| {
                warn("MUTATING ENTITY: {}", .{e});
                const idx = myecs.entities.manager.index_map.get(e) orelse @panic("ENTITY SHOULD HAVE AN INDEX?");
                const v = myecs.components.access(u32, .someothercomponent, idx) orelse @panic("SHOULD HAVE THIS COMPONENT?");
                warn("VAL: {}", .{v.*});
                var new: u32 = 1111;
                myecs.components.insert(myecs.allocator, .someothercomponent, idx, &new) catch @panic("FAILED TO INSERT COMPONENT");
                // v.* = @as(u32, 1111);
            }
        }
    }.run);

    try ecs.systems.register(SomeSystem{});

    var state = State{};
    try ecs.runSystems(&state);

    for ([_]MyEcs.EntityManager.EntityHandle{entity_b}) |e| {
        // _ = e;
        const got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, e.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(
            1111,
            got.*,
        );
    }
    std.debug.print("ENTITY MANAGEMENT WORKS AS EXPECTED\n", .{});
}

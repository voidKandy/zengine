const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
const warn = std.log.warn;
const Type = std.builtin.Type;
const Shape = zbt.Shape;
const Allocator = std.mem.Allocator;

/// Associates some `Data` type with a `u32` identifier
/// Currently used for managing `System`s and `Entity`s
fn IdentifierManager(
    MAX: comptime_int,
    Data: type,
) type {
    return struct {
        const Identifier = u32;
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
        data: [MAX]?Data = blk: {
            var all: [MAX]?Data = undefined;
            @memset(&all, null);
            break :blk all;
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
        pub fn register(
            self: *Self,
            data: Data,
        ) Error!struct { Identifier, usize } {
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
            self.data[self.count] = data;
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
                    const last_data = self.getData(last_reg.@"0") orelse @panic("No signature for last inserted?");
                    warn(
                        \\
                        \\ LAST REGISTERED EXISTS
                        \\ ID: {}
                        \\ IDX: {}
                        \\ SIG: {b}
                    , .{
                        last_reg.@"0",
                        last_reg.@"1",
                        last_data.mask,
                    });
                    self.index_map.put(last_reg.@"0", index) catch return error.Insert;
                    self.identifier_map.put(index, last_reg.@"0") catch return error.Insert;
                    self.data[index] = last_data;
                    self.data[last_reg.@"1"] = null;
                }
            }

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

        fn getData(self: Self, entity: Identifier) ?Data {
            const idx = self.index_map.get(entity) orelse return null;
            return self.data[idx];
        }
    };
}

pub const Component = struct { [:0]const u8, type };
pub const Entity = u32;

pub const EcsOptions = struct {
    max_entities: usize,
    max_systems: usize,
    State: type,
    components: []const Component,
    /// Since I'm unsure about whether the `Scene` function should be encapsulated within `ECS`
    /// I'm unsure about the inclusion of `Scene` parameters in `EcsOptions`
    max_cameras: usize = 5,
};

/// Entity Component System "Coordinator"
pub fn Ecs(
    comptime Options: EcsOptions,
) type {
    if (Options.max_entities == 0 or Options.max_systems == 0) {
        @compileError("Set Options.max_entities & Options.max_systems to at least 1!");
    }
    return struct {
        const ThisEcs = @This();
        pub const State = Options.State;
        pub const Signature = std.bit_set.IntegerBitSet(@intCast(Options.components.len));
        pub const ComponentsTag = ComponentsManager.Tag;
        /// Returns the signature associated with the given components
        pub fn componentsSignature(query: []ComponentsTag) Signature {
            var sig = Signature.initEmpty();
            for (query) |c| {
                sig.set(@intFromEnum(c));
            }
            return sig;
        }
        pub inline fn componentType(variant: ComponentsTag) type {
            const idx = @intFromEnum(variant);
            return Options.components[idx].@"1";
        }

        pub const QueryRule = enum {
            /// Signature must match EXACTLY the passed components
            exact,
            /// Signature must have AT LEAST the passed components
            at_least,
            /// Signature must have ANY of the passed components, fails if NONE match
            any,

            /// Some function for comparing one signature to another, returns true if the first signature passes the needed requirements
            const ComparisonFunction = *const fn (Signature, Signature) bool;
            pub fn cmpFn(rule: QueryRule) ComparisonFunction {
                return switch (rule) {
                    .at_least => struct {
                        fn cmp(sig: Signature, other: Signature) bool {
                            return sig.supersetOf(other);
                        }
                    }.cmp,
                    .exact => struct {
                        fn cmp(sig: Signature, other: Signature) bool {
                            return sig.eql(other);
                        }
                    }.cmp,
                    .any => struct {
                        fn cmp(sig: Signature, other: Signature) bool {
                            return !sig.intersectWith(other).eql(Signature.initEmpty());
                        }
                    }.cmp,
                };
            }
        };

        pub const QueryStatement = struct {
            rule: QueryRule,
            sig: Signature,
            pub fn new(rule: QueryRule, components: []const ComponentsTag) @This() {
                return .{ .rule = rule, .sig = componentsSignature(@constCast(components)) };
            }
        };

        pub const Query = struct {
            is: ?QueryStatement = null,
            is_not: ?QueryStatement = null,
        };

        const ComponentsManager = cmp_man: {
            const N = Options.components.len;
            const ComponentTag: type, const TypeArr: [N]type = blk: {
                var fields: [N]Type.EnumField = undefined;
                var types: [N]type = undefined;
                @memset(&fields, Type.EnumField{
                    .name = "",
                    .value = 0,
                });

                for (0.., Options.components, &types) |i, c, *t| {
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
                const Tag = ComponentTag;
                /// Each array corresponds with the components in the order they were passed
                arrays: [N][Options.max_entities]?*anyopaque,
                const Error = error{ InvalidType, OutOfMemory };
                inline fn tagType(which: Tag) type {
                    return TypeArr[@intFromEnum(which)];
                }

                pub fn init() @This() {
                    return @This(){ .arrays = arr: {
                        var arr: [N][Options.max_entities]?*anyopaque = undefined;
                        @memset(&arr, inner: {
                            var a: [Options.max_entities]?*anyopaque = undefined;
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

                /// expects to be passed `T` for `component`
                /// **NEVER** use multiple allocators for a single instance
                pub fn insert(self: *@This(), allocator: Allocator, which: Tag, idx: usize, component: anytype) Error!void {
                    switch (@typeInfo(@TypeOf(component))) {
                        .pointer => {
                            std.log.err(
                                \\ Cannot Pass Pointer types to this function
                                \\
                            , .{});
                            return error.InvalidType;
                        },
                        else => {},
                    }
                    inline for (TypeArr, 0..) |T, i| {
                        if (i == @intFromEnum(which) and @TypeOf(component) == T) {
                            const val_ptr = try allocator.create(T);
                            val_ptr.* = component;
                            self.arrays[@intFromEnum(which)][idx] = val_ptr;
                            return;
                        }
                    }
                    return error.InvalidType;
                }

                /// moves component at `idx` to `to_idx`
                /// Nullifies data that was previously at `to_idx`
                fn swap(self: *@This(), which: Tag, idx: usize, to_idx: usize) void {
                    var arr = self.arrays[@intFromEnum(which)];
                    const tmp = arr[idx];
                    arr[to_idx] = tmp;
                    arr[idx] = null;
                    self.arrays[@intFromEnum(which)] = arr;
                }

                pub fn removeNoReturn(self: *@This(), which: Tag, idx: usize) void {
                    self.arrays[@intFromEnum(which)][idx] = null;
                    return;
                }

                pub fn removeWithReturn(self: *@This(), T: type, which: Tag, idx: usize) ?*T {
                    const val = self.arrays[@intFromEnum(which)][idx];
                    self.removeNoReturn(which, idx);
                    return @alignCast(@ptrCast(val));
                }

                pub fn access(self: *@This(), T: type, which: Tag, idx: usize) ?*T {
                    const ptr = self.arrays[@intFromEnum(which)][idx] orelse return null;
                    if (@intFromPtr(ptr) % @alignOf(T) != 0) {
                        @panic("Misaligned pointer access in ECS component store");
                    }
                    return @alignCast(@ptrCast(ptr));
                }
            };
        };

        const EntityManager = struct {
            manager: IdentifierManager(Options.max_entities, Signature),

            fn init(allocator: Allocator) @This() {
                return .{ .manager = IdentifierManager(Options.max_entities, Signature).init(allocator) catch @panic("Could not create IdentifierManager for Entities") };
            }

            /// Creates an empty with an empty `Signature`
            pub fn register(self: *@This()) !EntityHandle {
                const id, const i = try self.manager.register(Signature.initEmpty());
                _ = i;
                var parent_ptr =
                    @as(*ThisEcs, @fieldParentPtr("entities", self));
                _ = &parent_ptr;

                return EntityHandle{
                    .ecs = parent_ptr,
                    .identifier = id,
                };
            }

            pub fn queryEntities(self: *@This(), allocator: std.mem.Allocator, query: Query) std.mem.Allocator.Error!?[]Entity {
                std.log.warn(
                    \\
                    \\ Running Query 
                , .{});
                var all = std.ArrayList(Entity).init(allocator);

                var entity_iter = self.manager.identifier_map.valueIterator();
                while (entity_iter.next()) |entity| {
                    const idx = self.manager.index_map.get(entity.*) orelse @panic("NO INDEX FOR ENTITY??");
                    const sig = self.manager.data[idx] orelse @panic("NO SIGNATURE FOR ENTITY??");

                    var is_match = true;
                    if (query.is) |is| {
                        std.log.warn(
                            \\
                            \\ Comparing sigs [IS]
                            \\ {b}
                            \\ {b}
                        , .{ sig.mask, is.sig.mask });
                        is_match = is.rule.cmpFn()(sig, is.sig);
                    }

                    var is_not_match = false;
                    if (query.is_not) |is_not| {
                        std.log.warn(
                            \\
                            \\ Comparing sigs [IS NOT]
                            \\ {b}
                            \\ {b}
                        , .{ sig.mask, is_not.sig.mask });

                        is_not_match = is_not.rule.cmpFn()(sig, is_not.sig);
                    }

                    if (is_match and !is_not_match) {
                        try all.append(entity.*);
                    }
                }

                if (all.items.len <= 0) {
                    all.deinit();
                    return null;
                }
                return try all.toOwnedSlice();
            }

            /// Returns the function by which `Entity`s are compared according to a `Query`'s rule
            /// Helper struct for easily managing any components associated with an entity
            const EntityHandle = struct {
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
                        const sig = self.ecs.entities.manager.getData(self.identifier) orelse @panic("No entity signature?");
                        var bit_idx_iter = sig.iterator(.{});
                        while (bit_idx_iter.next()) |i| {
                            const comp_enum: ComponentsTag = @enumFromInt(i);
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
                            const sig = self.ecs.entities.manager.getData(ent) orelse @panic("No entity signature?");
                            var bit_idx_iter = sig.iterator(.{});
                            while (bit_idx_iter.next()) |i| {
                                const comp_enum: ComponentsTag = @enumFromInt(i);
                                self.ecs.components.swap(comp_enum, prev_idx_of_moved_ent, idx);
                            }
                        }
                    }
                }

                pub fn removeComponent(self: *@This(), which: ComponentsTag, component: anytype) !void {
                    const idx = self.index() orelse @panic("NO INDEX?");
                    var sig = self.ecs.entities.manager.data[idx];
                    sig.unset(@intFromEnum(which));
                    self.ecs.components.removeWithReturn(@TypeOf(component), which, idx) orelse return error.ComponentRemovalFailure;
                }

                pub fn addComponent(self: *@This(), which: ComponentsTag, component: anytype) !void {
                    const idx = self.index() orelse @panic("NO INDEX?");
                    var sig = self.ecs.entities.manager.data[idx] orelse @panic("NO DATA?");
                    std.log.debug("sig: {b}\n", .{sig.mask});
                    sig.set(@intFromEnum(which));
                    std.log.debug("changed sig: {b}\n", .{sig.mask});
                    self.ecs.entities.manager.data[idx] = sig;
                    try self.ecs.components.insert(self.ecs.allocator, which, idx, component);
                }
            };
        };

        const SystemFn = *const fn ([]Entity, *ThisEcs, *Options.State) void;

        pub const System = struct {
            query: Query,
            runFn: SystemFn,
        };

        const SystemManager = IdentifierManager(Options.max_systems, System);

        /// this is an allocator returned by `ArenaAllocator.allocator()`
        allocator: Allocator,
        entities: EntityManager,
        /// Systems are currently run sequentially before draw calls
        /// * less than ideal * ?
        /// `System` struct are given pre-filtered entities
        systems: SystemManager,
        components: ComponentsManager,

        pub fn init(arena: *std.heap.ArenaAllocator) ThisEcs {
            const alloc = arena.allocator();
            return ThisEcs{
                .allocator = alloc,
                .entities = EntityManager.init(alloc),
                .systems = SystemManager.init(alloc) catch @panic("FAILED to initialize Systems Manager"),
                .components = ComponentsManager.init(),
            };
        }

        pub fn deinit(self: *ThisEcs) void {
            self.entities.manager.deinit(self.allocator);
            self.systems.deinit(self.allocator);
            self.components.deinit(self.allocator);
        }

        pub fn runSystems(self: *ThisEcs, scene: *ThisEcs.Scene) !void {
            {
                std.log.warn(
                    \\
                    \\ Running Camera Systems
                , .{});
                while (scene.currentCamera()) |c| {
                    if (try self.entities.queryEntities(self.allocator, c.system.query)) |entities| {
                        c.system.runFn(entities, self, &scene.state);
                    }
                }
            }

            std.log.warn(
                \\
                \\ Running Other Systems
            , .{});
            var systems_iter =
                self.systems.identifier_map.valueIterator();
            while (systems_iter.next()) |id| {
                const system = self.systems.getData(id.*) orelse return error.NoData;
                const entities_opt =
                    try self.entities.queryEntities(self.allocator, system.query);

                if (entities_opt) |entities| {
                    std.log.warn(
                        \\
                        \\ Got Entites Matching: {any}
                    , .{entities});
                    system.runFn(entities, self, &scene.state);
                } else {
                    std.log.warn(
                        \\
                        \\ No Entites Matching
                    , .{});
                }
            }
        }
        // Maybe should be moved outside of the juristiction of `ECS`
        pub const Scene = struct {
            /// The `query` argument is the set of components that either have an impact on the camera
            /// or are impacted by the camera in some way
            pub const CameraBundle = struct {
                camera: @import("raylib").Camera3D,
                system: ThisEcs.System,
            };

            const Self = @This();

            current: usize,
            amount: usize,
            /// Should be *tightly packed*
            /// No gaps of `null` between bundles
            /// To ensure this, the `remove` method moves the last camera to the index of the removed camera bundle
            cameras: [Options.max_cameras]?CameraBundle,
            state: State,

            pub fn init(
                state: State,
            ) Self {
                var cameras: [Options.max_cameras]?CameraBundle = undefined;
                @memset(&cameras, null);
                return .{
                    .state = state,
                    .current = 0,
                    .amount = 0,
                    .cameras = cameras,
                };
            }

            pub fn deinit(self: @This()) void {
                comptime {
                    if (!@hasDecl(State, "deinit"))
                        @compileError("State type must have a deinit method!!!");
                }
                self.state.deinit();
            }

            pub fn selectNextCamera(self: *Self) void {
                const next = self.current + 1;
                if ((next >= self.cameras.len) or self.cameras[next] == null) {
                    self.current = 0;
                } else {
                    self.current = next;
                }
            }

            pub fn selectPrevCamera(self: *Self) void {
                const prev = self.current - 1;
                if ((prev <= 0)) {
                    self.current = blk: {
                        var count: usize = 0;
                        while (self.cameras) |_| {
                            count += 1;
                        }
                        break :blk count;
                    };
                } else {
                    self.current = prev;
                }
            }

            pub fn selectCamera(self: *Self, idx: usize) !void {
                if (self.cameras[idx] == null) {
                    return error.NoCamera;
                }

                self.current = idx;
            }

            pub fn currentCamera(self: Self) ?CameraBundle {
                return self.cameras[self.current];
            }

            pub fn addCamera(self: *Self, cam: CameraBundle) void {
                var idx: usize = 0;
                for (self.cameras) |c| {
                    if (c == null) break;
                    idx += 1;
                }
                std.debug.assert(idx < Options.max_cameras);
                self.cameras[idx] = cam;
                self.amount += 1;
            }

            pub fn removeCamera(self: *Self, idx: usize) void {
                self.cameras[idx] = self.cameras[self.amount - 1];
                self.amount -= 1;
            }
        };
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
    const MyEcs = Ecs(.{
        .max_entities = 5,
        .max_systems = 5,
        .State = State,
        .components = &[_]Component{
            .{ "somecomponent", bool },
            .{ "othercomponent", u8 },
            .{ "someothercomponent", u32 },
        },
    });
    var ecs = MyEcs.init(&arena);
    defer ecs.deinit();

    // Entity Initialization
    // ---
    const entity_a: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        const someother: u32 = 5;
        try handle.addComponent(MyEcs.ComponentsTag.someothercomponent, someother);
        const some: bool = false;
        try handle.addComponent(MyEcs.ComponentsTag.somecomponent, some);
        break :a handle;
    };

    const entity_b: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        const someother: u32 = 7;
        try handle.addComponent(MyEcs.ComponentsTag.someothercomponent, someother);
        const some: bool = true;
        try handle.addComponent(MyEcs.ComponentsTag.somecomponent, some);
        break :a handle;
    };

    var entity_c: MyEcs.EntityManager.EntityHandle = a: {
        const handle = try ecs.entities.register();
        break :a handle;
    };

    // Entity Component Validation
    // ---
    {
        const got = ecs.components.access(u32, MyEcs.ComponentsTag.someothercomponent, entity_a.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, 5);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsTag.somecomponent, entity_a.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, false);
    }
    {
        const got = ecs.components.access(u32, MyEcs.ComponentsTag.someothercomponent, entity_b.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, 7);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsTag.somecomponent, entity_b.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(got.*, true);
    }
    {
        const got = ecs.components.access(bool, MyEcs.ComponentsTag.somecomponent, entity_c.index().?);
        try std.testing.expect(got == null);
    }

    var all: [5]Entity = undefined;
    @memset(&all, 0);

    const query = MyEcs.Query{ .is = .{ .rule = .exact, .sig = s: {
        var s = MyEcs.Signature.initEmpty();
        s.set(@intFromEnum(MyEcs.ComponentsTag.somecomponent));
        s.set(@intFromEnum(MyEcs.ComponentsTag.someothercomponent));
        break :s s;
    } } };

    const matching = try ecs.entities.queryEntities(arena.allocator(), query) orelse @panic("NOTHING MATCHING");

    std.log.debug("got matching: {any}\n", .{matching});
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_a.identifier));
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_b.identifier));

    // Component Removal
    // ---

    {
        const removed = ecs.components.removeWithReturn(bool, MyEcs.ComponentsTag.somecomponent, entity_a.index().?) orelse @panic("nothing at that index");
        try std.testing.expectEqual(removed.*, false);
        try std.testing.expectEqual(null, ecs.components.access(bool, MyEcs.ComponentsTag.somecomponent, entity_a.index().?));
    }

    // Entity Index Storage
    // ---
    {
        try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_a.identifier));
        try std.testing.expectEqual(1, ecs.entities.manager.index_map.get(entity_b.identifier));
        try std.testing.expectEqual(2, ecs.entities.manager.index_map.get(entity_c.identifier));

        // adding component to `entity_c` to make sure the component data is moved as expected
        const val: u8 = 64;
        try entity_c.addComponent(.othercomponent, val);

        try entity_a.destroy();
        try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_c.identifier));
        try std.testing.expectEqual(0, entity_c.index().?);

        const got = ecs.components.access(u8, .othercomponent, entity_c.index().?);
        try std.testing.expectEqual(val, got.?.*);
    }
    // Systems
    // ---
    const SomeSystem = MyEcs.System{
        .query = MyEcs.Query{
            .is = MyEcs.QueryStatement.new(.at_least, &[_]MyEcs.ComponentsTag{.someothercomponent}),
        },
        .runFn = struct {
            fn run(entities: []Entity, myecs: *MyEcs, state: *State) void {
                _ = state;
                warn("IN SOME SYSTEM\n", .{});
                for (entities) |e| {
                    warn("MUTATING ENTITY: {}", .{e});
                    const idx = myecs.entities.manager.index_map.get(e) orelse @panic("ENTITY SHOULD HAVE AN INDEX?");
                    const v = myecs.components.access(u32, .someothercomponent, idx) orelse @panic("SHOULD HAVE THIS COMPONENT?");
                    warn("VAL: {}", .{v.*});
                    const new: u32 = 1111;
                    myecs.components.insert(myecs.allocator, .someothercomponent, idx, new) catch @panic("FAILED TO INSERT COMPONENT");
                    // v.* = @as(u32, 1111);
                }
            }
        }.run,
    };

    _ = try ecs.systems.register(SomeSystem);

    // var state = State{};
    var scene = MyEcs.Scene.init(State{});
    try ecs.runSystems(&scene);

    for ([_]MyEcs.EntityManager.EntityHandle{entity_b}) |e| {
        const got = ecs.components.access(u32, MyEcs.ComponentsTag.someothercomponent, e.index().?) orelse @panic("Nothing at that index");
        try std.testing.expectEqual(
            1111,
            got.*,
        );
    }
    std.debug.print("ENTITY MANAGEMENT WORKS AS EXPECTED\n", .{});
}

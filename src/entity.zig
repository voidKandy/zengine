const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
const warn = std.log.warn;
const Type = std.builtin.Type;
const Shape = zbt.Shape;

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

    var ecs = MyEcs.init(arena.allocator());
    defer ecs.deinit(arena.allocator());

    // Entity Initialization
    // ---
    const entity_a: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        const someother: u32 = 5;
        handle.add_component(MyEcs.ComponentsEnum.someothercomponent, &someother);
        const some: bool = false;
        handle.add_component(MyEcs.ComponentsEnum.somecomponent, &some);
        break :a handle;
    };

    const entity_b: MyEcs.EntityManager.EntityHandle = a: {
        var handle = try ecs.entities.register();
        const someother: u32 = 7;
        handle.add_component(MyEcs.ComponentsEnum.someothercomponent, &someother);
        const some: bool = true;
        handle.add_component(MyEcs.ComponentsEnum.somecomponent, &some);
        break :a handle;
    };

    const entity_c: MyEcs.EntityManager.EntityHandle = a: {
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

    std.log.warn("got matching: {any}\n", .{matching});
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_a.identifier));
    try std.testing.expect(std.mem.containsAtLeastScalar(Entity, matching, 1, entity_b.identifier));

    // Component Removal
    // ---
    {
        const removed = ecs.components.remove(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.index().?) orelse @panic("nothing at that index");
        try std.testing.expectEqual(removed.*, false);
        try std.testing.expect(ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.index().?) == null);
    }

    // Entity Index Storage
    // ---
    try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_a.identifier));
    try std.testing.expectEqual(1, ecs.entities.manager.index_map.get(entity_b.identifier));
    try std.testing.expectEqual(2, ecs.entities.manager.index_map.get(entity_c.identifier));

    try ecs.entities.manager.remove(arena.allocator(), entity_a.identifier);
    try std.testing.expectEqual(0, ecs.entities.manager.index_map.get(entity_c.identifier));
    try std.testing.expectEqual(0, entity_c.index().?);

    // Systems
    // ---
    const SomeSystem = MyEcs.System(&[_]MyEcs.ComponentsEnum{MyEcs.ComponentsEnum.somecomponent}, struct {
        fn run(entities: []Entity, myecs: *MyEcs, state: *State) void {
            std.log.warn("IN SOME SYSTEM\n", .{});
            _ = state;
            _ = myecs;
            _ = entities;
        }
    }.run);

    try ecs.systems.register_system(SomeSystem{});

    var state = State{};
    try ecs.runSystems(&state);

    std.debug.print("ENTITY MANAGEMENT WORKS AS EXPECTED\n", .{});
}

pub const Component = struct { [:0]const u8, type };

pub fn ComponentsData(
    MaxNEntities: comptime_int,
    comptime Components: []const Component,
) type {
    // each field is an array of the type passed for each component
    const N = Components.len;
    const ComponentTag, const TypeArr = blk: {
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

    return struct {
        const Enum = ComponentTag;
        arrays: [N][MaxNEntities]?*anyopaque,

        const Error = error{Type};

        inline fn tag_type(which: Enum) type {
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

        // Currently no way to cleanup component data
        // pub fn deinit(self: *@This()) void {

        // }

        /// expects to be passed `*const T` for `component`
        /// Unline `remove` and `access`, does not require passing the type
        pub fn insert(self: *@This(), which: Enum, idx: usize, component: anytype) void {
            self.arrays[@intFromEnum(which)][idx] = @ptrCast(@constCast(component));
        }

        /// I dont love that this requires `T` be passed in
        pub fn remove(self: *@This(), T: type, which: Enum, idx: usize) ?*T {
            // if (TypeArr[@intFromEnum(which)] != T) {
            //     return error.TypeMismatch;
            // }
            const val = self.arrays[@intFromEnum(which)][idx];
            self.arrays[@intFromEnum(which)][idx] = null;
            return @alignCast(@ptrCast(val));
        }

        pub fn access(self: *@This(), T: type, which: Enum, idx: usize) ?*T {
            // if (TypeArr[@intFromEnum(which)] != T) {
            //     return error.TypeMismatch;
            // }
            return @alignCast(@ptrCast(self.arrays[@intFromEnum(which)][idx]));
        }
    };
}

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
        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            defer self.index_map.deinit();
            defer self.identifier_map.deinit();
            var current = self.available_ids;
            while (current.next) |n| {
                allocator.destroy(current);
                current = n;
            }
            allocator.destroy(current);
        }

        pub fn init(allocator: std.mem.Allocator) Error!Self {
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
        pub fn register(
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

        // Allocates Queue node for the removed entity
        pub fn remove(self: *Self, allocator: std.mem.Allocator, entity: Identifier) Error!void {
            const index = self.index_map.get(entity) orelse return error.NoIndex;
            const last_sig = self.signatures[self.count - 1];
            const last_ent = self.identifier_map.get(self.count - 1) orelse return error.NoIdentifier;
            warn(
                \\
                \\ REMOVING ENTITY: {}
                \\ IDX: {}
                \\ LAST SIGNATURE REGISTERED: {b}
                \\ LAST ENTITY REGISTERED: {}
            , .{ entity, index, last_sig.mask, last_ent });

            self.index_map.put(last_ent, index) catch return error.Insert;
            self.identifier_map.put(index, last_ent) catch return error.Insert;
            self.signatures[index] = last_sig;
            self.signatures[self.count - 1] = Signature.initEmpty();

            const node = allocator.create(IdQueue.Node) catch return error.OutOfMemory;
            node.* = IdQueue.Node{ .next = null, .data = entity };
            var current: *IdQueue.Node = self.available_ids.next orelse @panic("EMPTY IDS?");
            while (current.next) |next| {
                current = next;
            }
            current.next = node;
            self.count -= 1;
            warn(
                \\ NEW COUNT: {}
            , .{self.count});
            return;
        }

        /// Gets all entities who have at least all the bits that are set in the given signature set
        pub fn getBySignatureAtLeast(self: Self, buffer: *[MAX]Identifier, signature: Self.Signature) ?[]Identifier {
            var amt: usize = 0;
            for (0.., self.signatures) |i, sig| {
                if (signature.subsetOf(sig)) {
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

        /// Gets all entities that match the given signature *exactly*
        pub fn getBySignatureExact(self: Self, buffer: *[MAX]Identifier, signature: Self.Signature) ?[]Identifier {
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

        pub fn getSignature(self: Self, entity: Identifier) ?Self.Signature {
            const idx = self.index_map.get(entity) orelse return null;
            return self.signatures[idx];
        }
        // fn register_component_for_entity(self: *Self, entity: Identifier, component: anytype) void {}
    };
}

pub const Entity = u32;
// const System = struct { [:0]const u8, *const fn() };
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

        const ComponentsManager =
            ComponentsData(MaxNEntities, Components);

        const EntityManager = struct {
            manager: IdentifierManager(MaxNEntities, Components.len),

            fn init(allocator: std.mem.Allocator) @This() {
                return .{ .manager = IdentifierManager(MaxNEntities, Components.len).init(allocator) catch @panic("Could not create IdentifierManager for Entities") };
            }

            /// I dont think I like having this behavior like this
            /// Not because it's BAD, but because it presents inconsitencies
            pub const EntityHandle = struct {
                ecs: *ThisEcs,
                identifier: Entity,

                /// Is `null` if the entity has been removed
                pub fn index(self: @This()) ?usize {
                    return self.ecs.entities.manager.index_map.get(self.identifier);
                }
                pub fn add_component(self: *@This(), which: ComponentsEnum, component: anytype) void {
                    const idx = self.index() orelse @panic("NO INDEX?");
                    // const signature = self.ecs.get_signature(&[_]ComponentsEnum{component});
                    var sig = self.ecs.entities.manager.signatures[idx];
                    std.log.warn("sig: {b}\n", .{sig.mask});
                    sig.set(@intFromEnum(which));
                    std.log.warn("changed sig: {b}\n", .{sig.mask});
                    self.ecs.entities.manager.signatures[idx] = sig;
                    self.ecs.components.insert(which, idx, component);
                }
            };

            pub fn register(self: *@This()) !EntityHandle {
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
        };

        const SystemFn = *const fn ([]Entity, *ThisEcs, *State) void;

        fn System(
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
            manager: IdentifierManager(MaxNSystems, Components.len),
            all_sys_fns: [MaxNSystems]?SystemFn = a: {
                var a: [MaxNSystems]?SystemFn = undefined;
                @memset(&a, null);
                break :a a;
            },

            pub fn init(allocator: std.mem.Allocator) @This() {
                return .{ .manager = IdentifierManager(MaxNSystems, Components.len).init(allocator) catch @panic("Failed to crate id manager for systems") };
            }
            pub fn register_system(self: *@This(), system: anytype) !void {
                const system_id, const system_idx = try self.manager.register();
                // _ = system;
                // _ = system_idx;
                std.log.warn("REGISTERED SYSTEM WITH ID: {} INTO ECS", .{system_id});
                self.manager.signatures[system_idx] = system.signature;
                self.all_sys_fns[system_idx] = system.func;
            }
        };

        entities: EntityManager,
        systems: SystemManager,
        components: ComponentsManager,

        pub fn init(alloc: std.mem.Allocator) ThisEcs {
            return ThisEcs{
                .entities = EntityManager.init(alloc),
                .systems = SystemManager.init(alloc),
                .components = ComponentsManager.init(),
            };
        }

        pub fn deinit(self: *ThisEcs, allocator: std.mem.Allocator) void {
            self.entities.manager.deinit(allocator);
            self.systems.manager.deinit(allocator);
        }

        pub fn runSystems(self: *ThisEcs, state: *State) !void {
            var iter =
                self.systems.manager.identifier_map.iterator();
            while (iter.next()) |e| {
                const id = e.value_ptr;
                const idx = e.key_ptr;

                if (self.systems.manager.getSignature(id.*)) |sig| {
                    var all: [MaxNEntities]Entity = undefined;
                    @memset(&all, 0);
                    if (self.entities.manager.getBySignatureExact(&all, sig)) |entities| {
                        if (self.systems.all_sys_fns[idx.*]) |func| {
                            func(entities, self, state);
                        }
                    }
                }

                // const components = self.components.arrays

                // if (self.systems.funcs[idx]) |f| {
                // should return an of entites matching the signature *exactly*
                // const entities = self.entities.get_matching_signature(sig);
                // f(entities);

            }
        }

        // pub fn get_components_by_signature(self: *ThisEcs, signature: ThisEcs.Signature) [] {
        // }

        // pub fn insertComponentIntoEntity(self: *ThisEcs, entity: Entity, which: ComponentsEnum, component: anytype) void {
        //     const index: usize = self.entities.index_map.get(entity);
        //     self.components.insert(which, index, component);
        //     self.entities.signatures[index].set(@intFromEnum(which));
        //     // self.components.arrays[@intFromEnum(which)][index] = c
        // }
    };
}

// test "entity manager" {
//     const Manager =
//         EntityManager(5, 3);
//     const allocator = std.testing.allocator;
//     var arena = std.heap.ArenaAllocator.init(allocator);
//     defer arena.deinit();
//     var manager = try Manager.init(arena.allocator());
//     const entity_a = try manager.register(sig: {
//         var s = Manager.Signature.initEmpty();
//         s.toggle(0);
//         break :sig s;
//     });
//     const entity_b = try manager.register(sig: {
//         var s = Manager.Signature.initEmpty();
//         s.toggle(2);
//         break :sig s;
//     });
//     const entity_c = try manager.register(sig: {
//         var s = Manager.Signature.initEmpty();
//         s.toggle(1);
//         break :sig s;
//     });

//     defer {
//         warn("MAP: {}", .{manager.index_map});
//     }
//     try std.testing.expectEqual(0, manager.index_map.get(entity_a));
//     try std.testing.expectEqual(1, manager.index_map.get(entity_b));

//     try manager.remove(arena.allocator(), entity_a);
//     const entity_d = try manager.register(Manager.Signature.initFull());
//     _ = entity_d;

//     try std.testing.expectEqual(0, manager.index_map.get(entity_c));
//     try std.testing.expect(manager.signatures[0].isSet(1));
// }

// IMPLEMENT AS A SYSTEM
// pub fn draw(state: *) anyerror!void {
//     // warn("DRAWING: {any}\n", .{self.transform});
//     const material: rl.Material =
//         mat: switch (self.material) {
//             .color => |c| {
//                 var material = try rl.loadMaterialDefault();
//                 material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = c;
//                 break :mat material;
//             },
//             .material => |m| {
//                 break :mat m;
//             },
//         };
//     rl.drawMesh(self.mesh, material, self.transform);
// }

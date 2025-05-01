const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
const warn = std.log.warn;
const Type = std.builtin.Type;
const State = core.state.State;
const Shape = zbt.Shape;

test "ECS Entity Management" {
    std.testing.refAllDecls(@This());
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print("\n\n---\nINIT ECS TEST\n---\n", .{});

    const MyEcs = Ecs(5, 5, &[_]Component{
        .{ "somecomponent", bool },
        .{ "othercomponent", u8 },
        .{ "someothercomponent", u32 },
    });

    var ecs = MyEcs.init(arena.allocator());
    defer ecs.deinit(arena.allocator());
    const entity_a: MyEcs.EntityManager.EntityHandle = try ecs.entities.register();

    // const entity_a = try ecs.entities.register(sig: {
    //     var s = MyEcs.Signature.initEmpty();
    //     s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
    //     break :sig s;
    // });

    // This is how component data can be added to entities
    const someother: u32 = 5;
    entity_a.add_component(MyEcs.ComponentsEnum.someothercomponent, &someother);
    const some: bool = false;
    entity_a.add_component(MyEcs.ComponentsEnum.somecomponent, &some);

    const SomeSystem = MyEcs.System(&[_]MyEcs.ComponentsEnum{MyEcs.ComponentsEnum.somecomponent}, struct {
        fn run(entities: []Entity, myecs: *MyEcs) void {
            std.log.warn("IN SOME SYSTEM\n", .{});
            _ = myecs;
            _ = entities;
        }
    }.run);

    // this is how systems can be registered
    try ecs.systems.register_system(SomeSystem{});
    try ecs.run_systems();
    // ecs.components.insert(MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1", &someother);
    // const got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1") orelse @panic("Nothing at that index");
    // try std.testing.expectEqual(got.*, someother);
    // _ = ecs.components.remove(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1") orelse @panic("nothing at that index");
    // const try_got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1");
    // try std.testing.expect(try_got == null);

    // const some: bool = true;
    // ecs.components.insert(MyEcs.ComponentsEnum.somecomponent, entity_a.@"1", &some);
    // const got_some = ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.@"1") orelse @panic("Nothing at that index");
    // try std.testing.expectEqual(got_some.*, some);
    // _ = ecs.components.remove(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.@"1") orelse @panic("nothing at that index");
    // const try_got_some = ecs.components.access(bool, MyEcs.ComponentsEnum.somecomponent, entity_a.@"1");
    // try std.testing.expect(try_got_some == null);

    // const entity_b = try ecs.entities.register(sig: {
    //     var s = MyEcs.Signature.initEmpty();
    //     s.toggle(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
    //     break :sig s;
    // });
    // const entity_c = try ecs.entities.register(sig: {
    //     var s = MyEcs.Signature.initEmpty();
    //     s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
    //     break :sig s;
    // });

    // try std.testing.expectEqual(0, ecs.entities.index_map.get(entity_a.@"0"));
    // try std.testing.expectEqual(1, ecs.entities.index_map.get(entity_b.@"0"));

    // try ecs.entities.remove(arena.allocator(), entity_a.@"0");
    // const entity_d = try ecs.entities.register(MyEcs.Signature.initFull());

    // try std.testing.expectEqual(0, ecs.entities.index_map.get(entity_c.@"0"));
    // try std.testing.expect(ecs.entities.signatures[0].isSet(@intFromEnum(MyEcs.ComponentsEnum.othercomponent)));

    // try std.testing.expectEqual(2, ecs.entities.index_map.get(entity_d.@"0"));
    // try std.testing.expect(e: {
    //     var correct = true;
    //     const d_sig =
    //         ecs.entities.signatures[2];
    //     correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.somecomponent));
    //     correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
    //     correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
    //     break :e correct;
    // });

    std.debug.print("ENTITY MANAGEMENT WORKS AS EXPECTED\n", .{});
}

// test "ECS System Management" {
//     std.testing.refAllDecls(@This());
//     const allocator = std.testing.allocator;
//     var arena = std.heap.ArenaAllocator.init(allocator);
//     defer arena.deinit();

//     std.debug.print("\n\n---\nINIT ECS TEST\n---\n", .{});

//     const MyEcs = Ecs(5, 2, &[_]Component{
//         .{ "somecomponent", u32 },
//         .{ "othercomponent", bool },
//         .{ "someothercomponent", u16 },
//     });

//     var ecs = MyEcs.init(arena.allocator());
//     defer ecs.deinit(arena.allocator());

//     const entity_a = try ecs.entities.register(sig: {
//         var s = MyEcs.Signature.initEmpty();
//         s.toggle(@intFromEnum(MyEcs.ComponentsEnum.somecomponent));
//         break :sig s;
//     });
//     const entity_b = try ecs.entities.register(sig: {
//         var s = MyEcs.Signature.initEmpty();
//         s.toggle(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
//         break :sig s;
//     });
//     const entity_c = try ecs.entities.register(sig: {
//         var s = MyEcs.Signature.initEmpty();
//         s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
//         break :sig s;
//     });
//     const entity_d = try ecs.entities.register(MyEcs.Signature.initFull());
//     _ = entity_a;
//     _ = entity_b;
//     _ = entity_c;
//     _ = entity_d;

//     try ecs.register_system(sig: {
//         var s = MyEcs.Signature.initEmpty();
//         s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
//         break :sig s;
//     }, basic_system);
// }

const Component = struct { [:0]const u8, type };

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
                warn("Added ID: {} to queue\n", .{id});
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

        pub fn get_matching_signature(self: Self, signature: Self.Signature) []Identifier {
            var all: [MAX]Identifier = undefined;
            for (0.., self.signatures, &all) |i, sig, *id| {
                if (signature.eql(sig)) {
                    id.* = self.identifier_map.get(i) orelse @panic("NO MATCHING IDENTIFIER FOR THAT INDEX");
                }
            }
            return &all;
        }

        pub fn get_signature(self: Self, entity: Identifier) ?Self.Signature {
            const idx = self.index_map.get(entity) orelse return null;
            return self.signatures[idx];
        }
        // fn register_component_for_entity(self: *Self, entity: Identifier, component: anytype) void {}
    };
}

const Entity = u32;
// const System = struct { [:0]const u8, *const fn() };
/// Entity Component System "Coordinator"
pub fn Ecs(
    MaxNEntities: comptime_int,
    MaxNSystems: comptime_int,
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
            pub const EntityHandle = struct {
                ecs: *ThisEcs,
                identifier: Entity,
                index: usize,

                pub fn add_component(self: @This(), which: ComponentsEnum, component: anytype) void {
                    // const signature = self.ecs.get_signature(&[_]ComponentsEnum{component});
                    self.ecs.entities.manager.signatures[self.index].set(@intFromEnum(which));
                    self.ecs.components.insert(which, self.index, component);
                }
            };

            fn register(self: *@This()) !EntityHandle {
                const id, const i = try self.manager.register();
                var parent_ptr =
                    @as(*ThisEcs, @fieldParentPtr("entities", self));
                _ = &parent_ptr;

                return EntityHandle{
                    .ecs = parent_ptr,
                    .identifier = id,
                    .index = i,
                };
            }
        };

        const SystemFn = *const fn ([]Entity, *ThisEcs) void;

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
                std.log.debug("REGISTERED SYSTEM WITH ID: {} INTO ECS", .{system_id});
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

        pub fn run_systems(self: *ThisEcs) !void {
            var iter =
                self.systems.manager.identifier_map.iterator();
            while (iter.next()) |e| {
                const id = e.value_ptr;
                const idx = e.key_ptr;

                if (self.systems.manager.get_signature(id.*)) |sig| {
                    const entities = self.entities.manager.get_matching_signature(sig);
                    if (self.systems.all_sys_fns[idx.*]) |func| {
                        func(entities, self);
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

        pub fn insert_component_into_entity(self: *ThisEcs, entity: Entity, which: ComponentsEnum, component: anytype) void {
            const index: usize = self.entities.index_map.get(entity);
            self.components.insert(which, index, component);
            self.entities.signatures[index].set(@intFromEnum(which));
            // self.components.arrays[@intFromEnum(which)][index] = c
        }
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

pub const OldEntity = struct {
    const MaterialTag = enum { color, material };
    pub const Material = union(MaterialTag) { color: (rl.Color), material: (rl.Material) };
    id: i32,
    mesh: rl.Mesh,
    material: Material,
    body: zbt.Body,
    /// Collision shape
    shape: Shape,
    /// 0.0 For static
    mass: f32,
    /// Column-major 4x4 matrix:
    /// | m0   m4   m8   m12 |   <- X axis + translation X
    /// | m1   m5   m9   m13 |   <- Y axis + translation Y
    /// | m2   m6   m10  m14 |   <- Z axis + translation Z
    /// | m3   m7   m11  m15 |   <- perspective row (typically 0 0 0 1)
    transform: rl.Matrix,

    const Self = @This();

    pub fn init(
        world: zbt.World,
        mesh: rl.Mesh,
        material: Material,
        shape: Shape,
        mass: f32,
        transform: rl.Matrix,
    ) Self {
        const id = world.getNumBodies();
        const body = zbt.initBody(
            mass,
            &[_]f32{
                transform.m0,
                transform.m4,
                transform.m8,

                transform.m1,
                transform.m5,
                transform.m9,

                transform.m2,
                transform.m6,
                transform.m10,

                transform.m12,
                transform.m13,
                transform.m14,
            },
            shape,
        );

        world.addBody(body);

        return Self{
            .id = id,
            .body = body,
            .mass = mass,
            .material = material,
            .shape = shape,
            .mesh = mesh,
            .transform = transform,
        };
    }

    pub fn deinit(self: Self) void {
        self.shape.deinit();
        self.body.deinit();
    }

    pub fn update(self: *Self, world: zbt.World) void {
        const body = world.getBody(self.id);
        var transform: [12]f32 = undefined;
        body.getGraphicsWorldTransform(&transform);

        self.transform.m0 = transform[0];
        self.transform.m4 = transform[1];
        self.transform.m8 = transform[2];

        self.transform.m1 = transform[3];
        self.transform.m5 = transform[4];
        self.transform.m9 = transform[5];

        self.transform.m2 = transform[6];
        self.transform.m6 = transform[7];
        self.transform.m10 = transform[8];

        self.transform.m12 = transform[9];
        self.transform.m13 = transform[10];
        self.transform.m14 = transform[11];
    }

    pub fn draw(self: *Self) anyerror!void {
        // warn("DRAWING: {any}\n", .{self.transform});
        const material: rl.Material =
            mat: switch (self.material) {
                .color => |c| {
                    var material = try rl.loadMaterialDefault();
                    material.maps[@as(usize, @intFromEnum(rl.MATERIAL_MAP_DIFFUSE))].color = c;
                    break :mat material;
                },
                .material => |m| {
                    break :mat m;
                },
            };
        rl.drawMesh(self.mesh, material, self.transform);
    }
};

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

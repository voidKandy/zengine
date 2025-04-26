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

    const MyEcs = Ecs(5, 0, &[_]Component{
        .{ "somecomponent", bool },
        .{ "othercomponent", u8 },
        .{ "someothercomponent", u32 },
    });

    var ecs = MyEcs.init(arena.allocator());
    defer ecs.deinit(arena.allocator());
    const entity_a = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
        break :sig s;
    });

    // This is how component data can be added to entities
    const someother: u32 = 5;
    ecs.components.insert(MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1", &someother);
    const got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1") orelse @panic("Nothing at that index");
    try std.testing.expectEqual(got.*, someother);
    _ = ecs.components.remove(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1") orelse @panic("nothing at that index");
    const try_got = ecs.components.access(u32, MyEcs.ComponentsEnum.someothercomponent, entity_a.@"1");
    try std.testing.expect(try_got == null);

    const entity_b = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
        break :sig s;
    });
    const entity_c = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
        break :sig s;
    });

    try std.testing.expectEqual(0, ecs.entities.index_map.get(entity_a.@"0"));
    try std.testing.expectEqual(1, ecs.entities.index_map.get(entity_b.@"0"));

    try ecs.entities.remove(arena.allocator(), entity_a.@"0");
    const entity_d = try ecs.entities.register(MyEcs.Signature.initFull());

    try std.testing.expectEqual(0, ecs.entities.index_map.get(entity_c.@"0"));
    try std.testing.expect(ecs.entities.signatures[0].isSet(@intFromEnum(MyEcs.ComponentsEnum.othercomponent)));

    try std.testing.expectEqual(2, ecs.entities.index_map.get(entity_d.@"0"));
    try std.testing.expect(e: {
        var correct = true;
        const d_sig =
            ecs.entities.signatures[2];
        correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.somecomponent));
        correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
        correct = d_sig.isSet(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
        break :e correct;
    });

    std.debug.print("ENTITY MANAGEMENT WORKS AS EXPECTED\n", .{});
}

fn basic_system(state: State) void {
    _ = state;
}
test "ECS System Management" {
    std.testing.refAllDecls(@This());
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    std.debug.print("\n\n---\nINIT ECS TEST\n---\n", .{});

    const MyEcs = Ecs(5, 2, &[_]Component{
        .{ "somecomponent", u32 },
        .{ "othercomponent", bool },
        .{ "someothercomponent", u16 },
    });

    var ecs = MyEcs.init(arena.allocator());
    defer ecs.deinit(arena.allocator());

    const entity_a = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.somecomponent));
        break :sig s;
    });
    const entity_b = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.someothercomponent));
        break :sig s;
    });
    const entity_c = try ecs.entities.register(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
        break :sig s;
    });
    const entity_d = try ecs.entities.register(MyEcs.Signature.initFull());
    _ = entity_a;
    _ = entity_b;
    _ = entity_c;
    _ = entity_d;

    try ecs.register_system(sig: {
        var s = MyEcs.Signature.initEmpty();
        s.toggle(@intFromEnum(MyEcs.ComponentsEnum.othercomponent));
        break :sig s;
    }, basic_system);
}

/// Simply an ID
const Entity = u32;
const Component = struct { [:0]const u8, type };

pub fn ComponentsData(
    MaxNEntities: comptime_int,
    comptime Components: []const Component,
) type {
    // each field is an array of the type passed for each component
    const N = Components.len;

    // const Fields: []Type.StructField = blk: {
    //     var fields: [N]Type.StructField = undefined;
    //     inline for (&fields, Components) |*f, c| {
    //         f.* = Type.StructField{
    //             .name = c.@"0",
    //             // .type = [Components.len]?c.@"1",
    //             // .default_value_ptr = &@as([Components.len]?c.@"1", empty: {
    //             //     var a: [Components.len]?c.@"1" = undefined;
    //             //     @memset(&a, null);
    //             //     break :empty a;
    //             // }),
    //             .type = [N]?*anyopaque,
    //             .default_value_ptr = &@as([N]?*anyopaque, empty: {
    //                 var a: [N]?*anyopaque = undefined;
    //                 @memset(&a, null);
    //                 break :empty a;
    //             }),
    //             .is_comptime = false,
    //             .alignment = @alignOf(c.@"1"),
    //         };
    //     }
    //     break :blk fields[0..];
    // };

    // const Inner = @Type(Type{ .@"struct" = Type.Struct{
    //     .is_tuple = false,
    //     .layout = Type.ContainerLayout.auto,
    //     .fields = Fields,
    //     .decls = @typeInfo(struct {}).@"struct".decls,
    // } });

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

    // const U = union(ComponentTag) {};
    // const Fields: []Type.StructField = blk: {
    //     var fields: [N]Type.StructField = undefined;
    //     inline for (&fields, Components) |*f, c| {
    //         f.* = Type.StructField{
    //             .name = c.@"0",
    //             // .type = [Components.len]?c.@"1",
    //             // .default_value_ptr = &@as([Components.len]?c.@"1", empty: {
    //             //     var a: [Components.len]?c.@"1" = undefined;
    //             //     @memset(&a, null);
    //             //     break :empty a;
    //             // }),
    //             .type = [N]?*anyopaque,
    //             .default_value_ptr = &@as([N]?*anyopaque, empty: {
    //                 var a: [N]?*anyopaque = undefined;
    //                 @memset(&a, null);
    //                 break :empty a;
    //             }),
    //             .is_comptime = false,
    //             .alignment = @alignOf(c.@"1"),
    //         };
    //     }
    //     break :blk fields[0..];
    // };

    return struct {
        const Enum = ComponentTag;
        // inner: Inner,
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

fn System(comptime T: type, N: comptime_int, comptime updateFn: fn (self: T, state: anytype) void) type {
    return struct {
        t: T,
        signature: std.bit_set.IntegerBitSet(@intCast(N)),

        /// idk abt this yet
        fn update(self: @This(), state: anytype) void {
            updateFn(self, state);
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
        signatures: [MAX]Signature,
        index_map: std.AutoHashMap(Identifier, usize),
        identifier_map: std.AutoHashMap(usize, Identifier),
        count: usize,

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

            var signatures: [MAX]Signature = undefined;
            @memset(&signatures, Signature.initEmpty());

            const idx_map = std.AutoHashMap(Identifier, usize).init(allocator);
            const ent_map = std.AutoHashMap(usize, Identifier).init(allocator);
            return Self{
                .available_ids = head,
                .signatures = signatures,
                .index_map = idx_map,
                .identifier_map = ent_map,
                .count = 0,
            };
        }

        /// Returns a tuple of the `Identifier` (`u32`) and the index
        pub fn register(self: *Self, sig: Signature) Error!struct { Identifier, usize } {
            defer {
                warn(
                    \\ SIGNATURE: {b}
                    \\ NEW COUNT: {}
                    \\ ARRAY: 
                , .{ sig.mask, self.count });
                inline for (self.signatures) |s| {
                    warn("{b}", .{s.mask});
                }
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
            self.signatures[self.count] = sig;
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

        pub fn get_signature(self: Self, entity: Identifier) Self.Signature {
            const idx = self.index_map.get(entity);
            return self.signatures[idx];
        }
        // fn register_component_for_entity(self: *Self, entity: Identifier, component: anytype) void {}
    };
}

/// Entity Component System "Coordinator"
pub fn Ecs(
    MaxNEntities: comptime_int,
    MaxNSystems: comptime_int,
    comptime Components: []const Component,
) type {
    return struct {
        const Signature = std.bit_set.IntegerBitSet(@intCast(Components.len));
        /// WIP!!
        const SystemFunction = *const fn (State) void;
        const ComponentsManager =
            ComponentsData(MaxNEntities, Components);
        const ComponentsEnum = ComponentsManager.Enum;
        const EntityManager = IdentifierManager(MaxNEntities, Components.len);
        const SystemManager = IdentifierManager(MaxNSystems, Components.len);

        entities: EntityManager,
        systems: struct {
            manager: SystemManager,
            funcs: [MaxNSystems]?SystemFunction = s: {
                var v: [MaxNSystems]?SystemFunction = undefined;
                @memset(&v, null);
                break :s v;
            },
        },
        components: ComponentsManager,

        fn init(alloc: std.mem.Allocator) @This() {
            return @This(){
                .entities = EntityManager.init(alloc) catch |e| {
                    std.log.err("ERROR: {}", .{e});
                    @panic("Failed to init Entity Manager");
                },
                .systems = .{ .manager = SystemManager.init(alloc) catch |e| {
                    std.log.err("ERROR: {}", .{e});
                    @panic("Failed to init Entity Manager");
                } },
                .components = ComponentsManager.init(),
            };
        }

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.entities.deinit(allocator);
            self.systems.manager.deinit(allocator);
        }

        fn register_system(self: *@This(), signature: Signature, func: SystemFunction) !void {
            const system_id, const system_idx = try self.systems.manager.register(signature);
            std.log.debug("REGISTERED SYSTEM WITH ID: {} INTO ECS", .{system_id});
            self.systems.funcs[system_idx] = func;
        }

        // fn insert_component_into_entity(self: Ecs, entity: Entity, component: anytype) void {
        //     const index: usize = self.entities.index_map.get(entity);
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

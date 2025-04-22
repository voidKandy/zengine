const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("root.zig");
const warn = std.log.warn;
const Type = std.builtin.Type;
const State = core.state.State;
const Shape = zbt.Shape;

test "ECS" {
    std.testing.refAllDecls(@This());
    const allocator = std.testing.allocator;
    std.debug.print("\n\n---\nINIT ECS TEST\n", .{});

    const MyEcs = Ecs(5, &[_]Component{
        .{ "somecomponent", u32 },
        .{ "othercomponent", bool },
    });

    const ecs = MyEcs.init(allocator);
    defer ecs.deinit(allocator);

    try std.testing.expect(false);
}

/// Simply an ID
const Entity = u32;

const Component = struct { [:0]const u8, type };

pub fn ComponentsData(
    comptime Components: []const Component,
) type {
    // each field is an array of the type passed for each component
    const N = Components.len;
    const Fields: []Type.StructField = blk: {
        var fields: [N]Type.StructField = undefined;
        inline for (&fields, Components) |*f, c| {
            // const FieldType = std.meta.Tuple{
            //     [Components.len]?c.@"1",
            //     usize,
            // };
            // var e: [Components.len]c.@"1" = undefined;
            // @memset(&e,* );
            // const empty = e;

            f.* = Type.StructField{
                .name = c.@"0",
                .type = [Components.len]c.@"1",
                .default_value_ptr = &@as([Components.len]c.@"1", undefined),
                .is_comptime = false,
                .alignment = @alignOf(c.@"1"),
            };
        }
        break :blk fields[0..];
    };

    const Inner = @Type(Type{ .@"struct" = Type.Struct{
        .is_tuple = false,
        .layout = Type.ContainerLayout.auto,
        .fields = Fields,
        .decls = @typeInfo(struct {}).@"struct".decls,
    } });

    return struct {
        inner: Inner,

        pub fn init() @This() {
            return @This(){ .inner = Inner{} };
        }
        // Appends to corresponding component array
        // fn append()
    };
}

// test "test component manager" {
//     const Cm = ComponentManager(5, &[_]type{
//         u32,
//     });
//     var cm = Cm.init();
//     cm.inner.u32[0] = 5;

//     try std.testing.expectEqual(5, cm.inner.u32[0]);
// }

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
/// Entity Component System "Coordinator"
pub fn Ecs(
    MaxNEntities: comptime_int,
    // MaxNComponents: comptime_int,
    comptime Components: []const Component,
) type {
    // Component use of entities is flagged by a single bit a bit set the size of the `Components` type array.
    // Each `Entity` has a `Signature`
    // Each `System` has a `Signature`
    const Signature = std.bit_set.IntegerBitSet(@intCast(Components.len));

    const SystemsEnum = blk: {
        var fields: [Components.len]Type.EnumField = undefined;
        @memset(&fields, Type.EnumField{
            .name = "",
            .value = 0,
        });

        for (0.., Components) |i, c| {
            fields[i] = Type.EnumField{
                .name = c.@"0",
                .value = i,
            };
        }
        break :blk @Type(Type{ .@"enum" = .{
            .tag_type = u32,
            .fields = &fields,
            .decls = &[_]Type.Declaration{},
            .is_exhaustive = true,
        } });
    };
    const SystemManager =
        struct {
            registered_systems: [Components.len]?Signature = blk: {
                var arr: [Components.len]?Signature = undefined;
                @memset(&arr, null);
                break :blk arr;
            },
            // _sys_enum: type = SystemsEnum,

            fn insert_system(self: @This(), Which: SystemsEnum, signature: Signature) void {
                warn("inserting system for {}", .{Which});
                if (self.registered_systems[@intFromEnum(Which)]) |_| {
                    @panic("WILL CLOBBER");
                }

                self.registered_systems[@intFromEnum(Which)] = signature;
            }

            fn delete_system(self: @This(), Which: SystemsEnum) void {
                warn("deleting system for {}", .{Which});
                self.registered_systems[@intFromEnum(Which)] = null;
            }
        };

    const EntityManager = struct {
        const EntityIdQueue = std.DoublyLinkedList(u32);
        const Self = @This();
        const Error = error{
            NoEntity,
            Insert,
            NoIndex,
            Random,
            OutOfMemory,
        };

        available_ids: *EntityIdQueue.Node,
        signatures: [MaxNEntities]Signature,
        index_map: std.AutoHashMap(Entity, usize),
        entity_map: std.AutoHashMap(usize, Entity),
        count: usize,

        /// requires the same allocator be passed as with `init`
        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            var current = self.available_ids;
            while (current.next) |n| {
                defer allocator.destroy(current);
                current = n;
            }
            defer allocator.destroy(current);
        }

        pub fn init(allocator: std.mem.Allocator) Error!Self {
            var prng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                std.posix.getrandom(std.mem.asBytes(&seed)) catch return error.Random;
                break :blk seed;
            });
            const rand = prng.random();

            const head = allocator.create(EntityIdQueue.Node) catch return error.OutOfMemory;
            head.* = EntityIdQueue.Node{ .next = null, .data = rand.int(u32) };
            var current = head;
            for (0..MaxNEntities) |_| {
                const id = rand.int(u32);
                warn("Added ID: {} to queue\n", .{id});
                const node = allocator.create(EntityIdQueue.Node) catch |e| {
                    std.log.err("Error: {}", .{e});
                    return error.OutOfMemory;
                };
                node.* = EntityIdQueue.Node{ .next = null, .data = id };
                current.next = node;
                current = node;
            }

            var signatures: [MaxNEntities]Signature = undefined;
            @memset(&signatures, Signature.initEmpty());

            const idx_map = std.AutoHashMap(Entity, usize).init(allocator);
            const ent_map = std.AutoHashMap(usize, Entity).init(allocator);
            return Self{
                .available_ids = head,
                .signatures = signatures,
                .index_map = idx_map,
                .entity_map = ent_map,
                .count = 0,
            };
        }

        pub fn register(self: *Self, sig: Signature) Error!Entity {
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

            const ent: Entity = ent: {
                const node = self.available_ids;
                const next = self.available_ids.next orelse return error.NoEntity;
                self.available_ids = next;
                break :ent node.data;
            };
            warn(
                \\ REGISTERING ENTITY: {}
                \\ COUNT: {}
            , .{ ent, self.count });
            self.index_map.put(ent, self.count) catch return error.Insert;
            self.entity_map.put(self.count, ent) catch return error.Insert;
            self.signatures[self.count] = sig;
            self.count += 1;

            return ent;
        }

        // Allocates Queue node for the removed entity
        pub fn remove(self: *Self, allocator: std.mem.Allocator, entity: Entity) Error!void {
            const index = self.index_map.get(entity) orelse return error.NoIndex;
            const last_sig = self.signatures[self.count - 1];
            const last_ent = self.entity_map.get(self.count - 1) orelse return error.NoEntity;
            warn(
                \\
                \\ REMOVING ENTITY: {}
                \\ IDX: {}
                \\ LAST SIGNATURE REGISTERED: {b}
                \\ LAST ENTITY REGISTERED: {}
            , .{ entity, index, last_sig.mask, last_ent });

            self.index_map.put(last_ent, index) catch return error.Insert;
            self.entity_map.put(index, last_ent) catch return error.Insert;
            self.signatures[index] = last_sig;
            self.signatures[self.count - 1] = Signature.initEmpty();

            const node = allocator.create(EntityIdQueue.Node) catch return error.OutOfMemory;
            node.* = EntityIdQueue.Node{ .next = null, .data = entity };
            var current: *EntityIdQueue.Node = self.available_ids.next orelse @panic("EMPTY IDS?");
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
        pub fn get_signature(self: Self, entity: Entity) Self.Signature {
            const idx = self.index_map.get(entity);
            return self.signatures[idx];
        }
        // fn register_component_for_entity(self: *Self, entity: Entity, component: anytype) void {}
    };

    return struct {
        entities: EntityManager,
        systems: SystemManager,
        components: ComponentsData(Components),

        fn init(alloc: std.mem.Allocator) @This() {
            return @This(){
                .entities = EntityManager.init(alloc) catch |e| {
                    std.log.err("ERROR: {}", .{e});
                    @panic("Failed to init Entity Manager");
                },
                .systems = SystemManager{},
                .components = ComponentsData(Components).init(),
            };
        }

        fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            self.entities.deinit(allocator);
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

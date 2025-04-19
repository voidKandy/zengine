const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("engine_core");
const warn = std.log.warn;
const State = core.state.State;
const Shape = zbt.Shape;

/// Simply an ID
const Entity = u32;

fn EntityManager(
    comptime MaxNEntities: usize,
    comptime MaxNComponents: usize,
) type {
    if (MaxNEntities <= 0) {
        @compileError("MaxNEntities MUST >= 0");
    }
    if (MaxNComponents <= 0) {
        @compileError("MaxNComponents MUST >= 0");
    }

    return struct {
        const Signature = std.bit_set.IntegerBitSet(@intCast(MaxNComponents));
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
                const node = allocator.create(EntityIdQueue.Node) catch return error.OutOfMemory;
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
    };
}

test "entity manager" {
    const Manager =
        EntityManager(5, 3);
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var manager = try Manager.init(arena.allocator());
    const entity_a = try manager.register(sig: {
        var s = Manager.Signature.initEmpty();
        s.toggle(0);
        break :sig s;
    });
    const entity_b = try manager.register(sig: {
        var s = Manager.Signature.initEmpty();
        s.toggle(2);
        break :sig s;
    });
    const entity_c = try manager.register(sig: {
        var s = Manager.Signature.initEmpty();
        s.toggle(1);
        break :sig s;
    });

    defer {
        warn("MAP: {}", .{manager.index_map});
    }
    try std.testing.expectEqual(0, manager.index_map.get(entity_a));
    try std.testing.expectEqual(1, manager.index_map.get(entity_b));

    try manager.remove(arena.allocator(), entity_a);
    const entity_d = try manager.register(Manager.Signature.initFull());
    _ = entity_d;

    try std.testing.expectEqual(0, manager.index_map.get(entity_c));
    try std.testing.expect(manager.signatures[0].isSet(1));
}

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

pub fn ComponentManager(
    MAX_COMPONENTS: comptime_int,
    comptime ComponentTypes: []const type,
) type {
    const N = ComponentTypes.len;
    const Fields: [N]std.builtin.Type.StructField = blk: {
        var fields: [N]std.builtin.Type.StructField = undefined;
        // need some default value
        @memset(&fields, std.builtin.Type.StructField{
            .name = "",
            .type = u1,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(u1),
        });
        inline for (0.., ComponentTypes) |i, t| {
            // this has to be called like this
            const name = @typeName(t);
            for (name) |ch| {
                if (std.ascii.isUpper(ch)) {
                    ch += 32;
                }
            }
            // defer warn("NAME: {s}\n", .{name});

            const _type = @Type(std.builtin.Type{ .array = std.builtin.Type.Array{ .len = MAX_COMPONENTS, .child = t, .sentinel_ptr = null } });
            fields[i] = std.builtin.Type.StructField{
                .name = name,
                .type = _type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(_type),
            };
        }
        break :blk fields;
    };

    const Phantom = struct {};

    return @Type(std.builtin.Type{ .@"struct" = std.builtin.Type.Struct{
        .is_tuple = false,
        .layout = std.builtin.Type.ContainerLayout.auto,
        .fields = &Fields,
        .decls = @typeInfo(Phantom).@"struct".decls,
    } });

    // var _type = @Type(std.builtin.Type {
    //     .@"struct"

    //     };

    // return _type;

}

test "test component manager" {
    const Cm = ComponentManager(5, &[_]type{
        u32,
    });
    const cm = Cm{ .u32 = [5]u32{ 0, 0, 0, 0, 0 } };
    try std.testing.expectEqual(cm.u32[0], 0);
}

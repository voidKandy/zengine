const rl = @import("raylib");
const std = @import("std");
const zbt = @import("zbullet");
const core = @import("engine_core");
const State = core.state.State;
const Shape = zbt.Shape;

const PhysicsSystem = System(
    zbt.World,
    struct { transform: rl.Matrix },
    error{},
    "physics",
    struct {
        fn ctx(state: State) error{}!zbt.World {
            return state.physics.world;
        }
    }.ctx,
    struct {
        fn update(ctx: zbt.World) error{}!zbt.World {}
    }.update,
);
// Should be moved to the State object
pub fn System(
    /// Essentially the *state* of the system
    comptime Context: type,
    comptime ComponentType: type,
    comptime Error: type,
    comptime Name: []const u8,
    comptime getCtx: fn (state: State) Error!Context,
    comptime updateFn: fn (ctx: Context, component: ComponentType) Error!void,
) type {
    // Component should allow users to make arbitrary things happen to it's
    // connected Entity based on the state (ctx) of the system
    return struct {
        ctx: Context,

        const Self = @This();

        fn from_state(state: State) Error!Self {
            const ctx = try getCtx(state);
            return Self{ .ctx = ctx };
        }

        fn get_components(state: State) Error![]ComponentType {
            // state.
        }

        fn update(self: Self) Error!void {
            return updateFn(self.ctx);
        }
    };
}

pub const EntityStorage = struct {
    // fn EntityComponent(comptime I: usize) type{
    //     return struct {
    //         entity_pointer: *Entity,
    //         component: ComponentTypes[I],
    //     };
    // }
    entities: std.ArrayList(Entity),
    components: []struct { system_id: []const u8, id: u32, _t: type },

    fn register_component(self: *@This(), comp: anytype) void {}
};
// pub const EntityStorage = struct {
// };
pub const Entity = struct {
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
        // std.log.warn("DRAWING: {any}\n", .{self.transform});
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

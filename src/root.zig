const std = @import("std");
pub const da = @import("dynamic_array.zig");
pub const entity = @import("entity.zig");
pub const state = @import("state.zig");

test {
    std.testing.refAllDecls(@This());
}

/// # Cloning Inscription
/// ---
const CardType = enum {
    Magic,
    Dead,
    Tech,
    Beast,
};

const Abilities =
    da.DynamicArray(AbilityTag, 5);
const Card = struct {
    type: CardType,
    attack: usize,
    defence: usize,
    abilities: Abilities,
};

fn AbilityFn(Context: type) type {
    return struct {
        trigger_fn: *const fn (Card, GameState) ?Context,
        activate: *const fn (Card, Context, *GameState) void,
    };
}

const AbilityTag = enum {
    pack,

    fn ability(self: AbilityTag) anyopaque {
        return switch (self) {
            .pack => PackAbility,
        };
    }
};

/// UNIMPLEMENTED
/// should be true if there are > 1 of other cards of the same type
fn in_pack(_: Card, _: GameState) ?bool {
    return .{ .in_pack = true };
}
/// UNIMPLEMENTED
/// Should somehow improve each card of matching type
fn pack_activate(_: Card, _: bool, _: *GameState) void {
    return true;
}
const PackAbility = AbilityFn(bool){
    .trigger_fn = in_pack,
    .activate = pack_activate,
};

fn wolf_abilites() Abilities {
    return Abilities.from(&[_]AbilityTag{AbilityTag.pack}) catch @panic("Failed to init wolf abilities");
}
fn empty_abilites() Abilities {
    return Abilities.from(&[_]AbilityTag{}) catch @panic("Failed to init empty abilities");
}

fn wolf_card() Card {
    return .{
        .type = CardType.Beast,
        .attack = 3,
        .defence = 2,
        .abilities = wolf_abilites(),
    };
}

fn boring_bot() Card {
    return .{
        .type = CardType.Tech,
        .attack = 1,
        .defence = 2,
        .abilities = empty_abilites(),
    };
}

const PlayerState =
    struct {
        const DECK_SIZE_MAX = 20;
        hand: da.DynamicArray(Card, 3),
        discard: da.DynamicArray(Card, 20),
        deck: da.DynamicArray(Card, DECK_SIZE_MAX),

        const Self = @This();

        /// Error can only be caused by the shuffle
        fn init_with_shuffle(deck: []const Card) !Self {
            std.log.warn("starting player state init\n", .{});
            var prng = std.Random.DefaultPrng.init(blk: {
                var seed: u64 = undefined;
                try std.posix.getrandom(std.mem.asBytes(&seed));
                break :blk seed;
            });
            const rand = prng.random();

            var touched_cards: [DECK_SIZE_MAX]u1 = undefined;
            @memset(&touched_cards, 0);
            var shuffled_deck = da.DynamicArray(Card, DECK_SIZE_MAX).init();

            for (0..deck.len) |_| {
                const rand_idx = rand_idx: {
                    var a = rand.intRangeLessThan(usize, 0, deck.len - 1);
                    while (touched_cards[a] == 1) {
                        if (std.mem.indexOfScalar(u1, &touched_cards, 1) != null) {
                            break;
                        }
                        a = rand.intRangeLessThan(usize, 0, deck.len - 1);
                    }
                    break :rand_idx a;
                };
                touched_cards[rand_idx] = 1;
                shuffled_deck.push(deck[rand_idx]) catch @panic("Malformed Shuffled Deck");
            }

            return Self{
                .deck = shuffled_deck,
                .hand = da.DynamicArray(Card, 3).init(),
                .discard = da.DynamicArray(Card, 20).init(),
            };
        }

        fn draw_cards(self: *Self, amt: usize) void {
            for (amt) |_| {
                const card = self.deck.pop() orelse break;
                self.hand.push_resize(card);
            }
        }
    };

const TimeOfDay =
    enum {
        morning,
        noon,
        afternoon,
        evening,
        night,

        fn next(self: *@This()) void {
            self.* = switch (self.*) {
                .morning => .noon,
                .noon => .afternoon,
                .afternoon => .evening,
                .evening => .night,
                .night => .morning,
            };
        }

        /// Does comptime time checks to ensure set Hours percentage total == 100
        fn percent(self: @This()) f32 {
            const morning: f32 = 0.1;
            const noon: f32 = 0.4;
            const afternoon: f32 = 0.2;
            const evening: f32 = 0.2;
            const night: f32 = 0.1;

            comptime {
                var p: f32 = 0.0;
                for (.{ morning, noon, afternoon, evening, night }) |v| {
                    p += v;
                }
                if (p != 1.0) {
                    @compileError("Invalid Cycle Percentages");
                }
            }

            return switch (self) {
                .morning => morning,
                .noon => noon,
                .afternoon => afternoon,
                .evening => evening,
                .night => night,
            };
        }
    };

fn DayNight(comptime HoursInDay: f32) type {
    return struct {
        current_time: f32,
        /// How many in-game hours should pass per real second
        cycle_speed: f32,
        time_of_day: TimeOfDay,

        const Self = @This();

        fn start(cycle_speed: f32) Self {
            return Self{
                .current_time = 0.0,
                .cycle_speed = cycle_speed,
                .time_of_day = .morning,
            };
        }

        fn update(self: *Self, dt: f32) void {
            self.current_time += dt * self.cycle_speed;

            // if (self.current_time >= 1.0) {
            //     self.current_time -= 1.0;
            // }

            const time_of_day = @mod(self.current_time + dt * self.cycle_speed, HoursInDay);

            const current_tod_cutoff = HoursInDay * self.time_of_day.percent();

            if (time_of_day >= current_tod_cutoff) {
                self.time_of_day.next();
            }
        }
    };
}

const GameState = struct {
    time: DayNight(24),
    player: PlayerState,
    opposer: PlayerState,
};

test "game state" {
    const deck =
        [_]Card{
            wolf_card(),
            boring_bot(),
        };
    // _ = deck;
    std.debug.print("STARTING TEST\n", .{});

    const player = try PlayerState.init_with_shuffle(&deck);
    const opposer = try PlayerState.init_with_shuffle(&deck);
    const st = GameState{ .time = DayNight(24).start(6.0), .player = player, .opposer = opposer };
    _ = st;
}

// test "DayNight advances through time-of-day stages" {
//     const HOURS_IN_DAY: f32 = 24.0;
//     const DayCycle = DayNight(HOURS_IN_DAY);
//     var cycle = DayCycle.start(6.0); // 6 in-game hours per real second

//     // Simulate time passing with constant dt
//     const dt = 1.0; // 1 second per tick
//     const num_steps = 5;

//     for (0..num_steps) |i| {
//         std.debug.print("Tick {}: TOD = {}\n", .{ i, cycle.time_of_day });
//         cycle.update(dt);
//     }

//     try std.testing.expectEqual(cycle.time_of_day, .afternoon);
// }

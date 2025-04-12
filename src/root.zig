const std = @import("std");
const da = @import("dynamic_array.zig");

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

const GameState = struct {
    player: PlayerState,
    opposer: PlayerState,
};

test {
    @import("std").testing.refAllDecls(@This());
}

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
    const state = GameState{ .player = player, .opposer = opposer };
    _ = state;
}

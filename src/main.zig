const std = @import("std");

////

// File masks prevent horizontal wraparound between adjacent ranks.
// Vertical bounds need no masks: bits shifted past bit 63 or below bit 0
// are discarded automatically.

// File a set to 1s.
//
// 8 1 . . . . . . .
// 7 1 . . . . . . .
// 6 1 . . . . . . .
// 5 1 . . . . . . .
// 4 1 . . . . . . .
// 3 1 . . . . . . .
// 2 1 . . . . . . .
// 1 1 . . . . . . .
//   a b c d e f g h
const FILE_A: u64 = 0x0101010101010101;

// File b set to 1s.
const FILE_B: u64 = 0x0202020202020202;

// File g set to 1s.
const FILE_G: u64 = 0x4040404040404040;

// File h set to 1s.
const FILE_H: u64 = 0x8080808080808080;

const RANK_1: u64 = 0x00000000000000FF;
const RANK_3: u64 = 0x0000000000FF0000;
const RANK_6: u64 = 0x0000FF0000000000;
const RANK_8: u64 = 0xFF00000000000000;

////

const Pieces = struct {
    // Non-sliders
    pawn: u64,
    knight: u64,
    king: u64,

    // Sliders
    orthogonal: u64, // rook + queen
    diagonal: u64, // bishop + queen
};

const Position = struct {
    white: u64,
    black: u64,
    pieces: Pieces,

    pub inline fn occupied(self: Position) u64 {
        return self.white | self.black;
    }

    pub inline fn queens(self: Position) u64 {
        return self.pieces.orthogonal & self.pieces.diagonal;
    }

    pub inline fn rook(self: Position) u64 {
        return self.pieces.orthogonal & ~self.pieces.diagonal;
    }

    pub inline fn bishop(self: Position) u64 {
        return ~self.pieces.orthogonal & self.pieces.diagonal;
    }
};

const Color = enum { black, white };

// zig fmt: off
const Square = enum(u6) {
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
};
// zig fmt: on

inline fn bit(square: Square) u64 {
    return @as(u64, 1) << @intFromEnum(square);
}

fn printBitboard(bitboard: u64) void {
    inline for (0..8) |i| {
        const rank = 7 - i;
        const rank_char: u8 = '1' + rank;

        var line = ". . . . . . . .".*;

        var row: u8 = @truncate(bitboard >> (rank * 8));

        while (row != 0) {
            const file = @ctz(row);

            line[file * 2] = '1';
            row &= row - 1;
        }

        std.debug.print("{c} {s}\n", .{ rank_char, line });
    }

    std.debug.print("  a b c d e f g h\n", .{});
}

inline fn shiftBy(bitboard: u64, shift_amount: i8) u64 {
    if (shift_amount >= 0)
        return bitboard >> shift_amount
    else
        return bitboard << -shift_amount;
}

inline fn knightAttacks(knights: u64) u64 {
    return (knights & ~(FILE_G | FILE_H)) << 10 |
        (knights & ~FILE_H) << 17 |
        (knights & ~FILE_A) << 15 |
        (knights & ~(FILE_A | FILE_B)) << 6 |
        (knights & ~(FILE_A | FILE_B)) >> 6 |
        (knights & ~FILE_A) >> 15 |
        (knights & ~FILE_H) >> 17 |
        (knights & ~(FILE_G | FILE_H)) >> 10;
}

inline fn kingAttacks(kings: u64) u64 {
    return (kings & ~FILE_H) << 1 |
        (kings & ~FILE_A) >> 1 |
        kings << 8 |
        kings >> 8 |
        (kings & ~FILE_A) << 7 |
        (kings & ~FILE_A) >> 9 |
        (kings & ~FILE_H) >> 7 |
        (kings & ~FILE_H) << 9;
}

inline fn pawnAttacks(pawns: u64, color: Color) u64 {
    switch (color) {
        .black => return (pawns & ~FILE_A) >> 9 |
            (pawns & ~FILE_H) >> 7,
        .white => return (pawns & ~FILE_A) << 7 |
            (pawns & ~FILE_H) << 9,
    }
}

inline fn pawnPushes(pawns: u64, occupied: u64, color: Color) u64 {
    const empty = ~occupied;

    const single_push = empty &
        (if (color == .black) pawns >> 8 else pawns << 8);

    const double_push_intermediates = single_push &
        if (color == .black) RANK_6 else RANK_3;

    const double_push = empty &
        (if (color == .black)
            double_push_intermediates >> 8
        else
            double_push_intermediates << 8);

    // Later we will want to return them separately rather than their union.
    return single_push | double_push;
}

//// SLIDERS ///////////////////////////////////////////////////////////////////

const RayWalking = struct {
    /// `piece` should contain exactly 1 bit set to 1.
    fn rayAttacks(
        piece: u64,
        occupied: u64,
        comptime border: u64,
        comptime shift_amount: i8,
    ) u64 {
        var attacks: u64 = 0;

        var current = piece;
        while (current & border == 0) {
            current = shiftBy(current, shift_amount);
            attacks |= current;
            if (current & occupied != 0) break;
        }

        return attacks;
    }

    /// Friendly pieces should be filtered later.
    inline fn rookAttacks(rook: u64, occupied: u64) u64 {
        return rayAttacks(rook, occupied, FILE_H, -1) |
            rayAttacks(rook, occupied, FILE_A, 1) |
            rayAttacks(rook, occupied, RANK_8, -8) |
            rayAttacks(rook, occupied, RANK_1, 8);
    }

    /// Friendly pieces should be filtered later.
    inline fn bishopAttacks(bishop: u64, occupied: u64) u64 {
        return rayAttacks(bishop, occupied, FILE_A | RANK_8, -7) |
            rayAttacks(bishop, occupied, FILE_A | RANK_1, 9) |
            rayAttacks(bishop, occupied, FILE_H | RANK_1, 7) |
            rayAttacks(bishop, occupied, FILE_H | RANK_8, -9);
    }

    /// Friendly pieces should be filtered later.
    inline fn queenAttacks(queen: u64, occupied: u64) u64 {
        return rookAttacks(queen, occupied) | bishopAttacks(queen, occupied);
    }
};

/// Should be initialized comptime:
/// const rays = comptime PrecomputedEmptyBoardRays.init();
const PrecomputedEmptyBoardRays = struct {
    north: [64]u64,
    south: [64]u64,
    east: [64]u64,
    west: [64]u64,

    north_east: [64]u64,
    north_west: [64]u64,
    south_east: [64]u64,
    south_west: [64]u64,

    fn init() PrecomputedEmptyBoardRays {
        var rays: PrecomputedEmptyBoardRays = undefined;

        inline for (0..64) |i| {
            const pos: u64 = 1 << i;
            rays.north[i] = RayWalking.rayAttacks(pos, 0, RANK_8, -8);
            rays.south[i] = RayWalking.rayAttacks(pos, 0, RANK_1, 8);
            rays.east[i] = RayWalking.rayAttacks(pos, 0, FILE_H, -1);
            rays.west[i] = RayWalking.rayAttacks(pos, 0, FILE_A, 1);

            rays.north_east[i] = RayWalking.rayAttacks(pos, 0, RANK_8 | FILE_H, -9);
            rays.north_west[i] = RayWalking.rayAttacks(pos, 0, RANK_8 | FILE_A, -7);
            rays.south_east[i] = RayWalking.rayAttacks(pos, 0, RANK_1 | FILE_H, 7);
            rays.south_west[i] = RayWalking.rayAttacks(pos, 0, RANK_1 | FILE_A, 9);
        }

        return rays;
    }

    /// Does not handle the case where x equals 0.
    /// @ctz(@as(u64, 0)) is 64, this doesn't fit in a u6 so we cast.
    inline fn lsbIndex(x: u64) u6 {
        return @intCast(@ctz(x));
    }

    /// Does not handle the case where x equals 0.
    inline fn msbIndex(x: u64) u6 {
        return @intCast(63 - @clz(x));
    }

    /// `piece` should contain exactly 1 bit set to 1.
    inline fn getAttacksForOrientation(
        piece: u64,
        rays: *const [64]u64,
        occupied: u64,
        scan: *const fn (u64) callconv(.@"inline") u6,
    ) u64 {
        const ray = rays[@ctz(piece)];
        const blockers = ray & occupied;

        var attacks: u64 = undefined;
        if (blockers == 0) attacks = ray else {
            const nearest_blocker = scan(blockers);
            attacks = ray & ~rays[nearest_blocker];
        }

        return attacks;
    }

    inline fn rookAttacks(
        self: *PrecomputedEmptyBoardRays,
        rook: u64,
        occupied: u64,
    ) u64 {
        return getAttacksForOrientation(rook, &self.north, occupied, lsbIndex) |
            getAttacksForOrientation(rook, &self.south, occupied, msbIndex) |
            getAttacksForOrientation(rook, &self.east, occupied, lsbIndex) |
            getAttacksForOrientation(rook, &self.west, occupied, msbIndex);
    }

    inline fn bishopAttacks(
        self: *PrecomputedEmptyBoardRays,
        bishop: u64,
        occupied: u64,
    ) u64 {
        return getAttacksForOrientation(bishop, &self.north_east, occupied, lsbIndex) |
            getAttacksForOrientation(bishop, &self.north_west, occupied, lsbIndex) |
            getAttacksForOrientation(bishop, &self.south_east, occupied, msbIndex) |
            getAttacksForOrientation(bishop, &self.south_west, occupied, msbIndex);
    }

    inline fn queenAttacks(
        self: *PrecomputedEmptyBoardRays,
        queen: u64,
        occupied: u64,
    ) u64 {
        return rookAttacks(self, queen, occupied) |
            bishopAttacks(self, queen, occupied);
    }
};

pub fn main() void {
    const rays = comptime PrecomputedEmptyBoardRays.init();

    const piece = bit(.d4);
    const occupied = bit(.d2) | bit(.b6);
    printBitboard(rays.queenAttacks(piece, occupied));
}

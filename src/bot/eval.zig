const ZChess = @import("zchess");
const std = @import("std");
const PST = @import("squaretables.zig");

pub const MATE_VALUE: i32 = 32000;
pub const MATE_THRESHOLD: i32 = 31000;

const pieceValues = [_]i32{
    100,
    320,
    330,
    500,
    900,
    20000,
};

const ptypes = [_]ZChess.PieceType{
    .Pawn,
    .Knight,
    .Bishop,
    .Rook,
    .Queen,
};

const ptypes_all = [_]ZChess.PieceType{
    .Pawn,
    .Knight,
    .Bishop,
    .Rook,
    .Queen,
    .King,
};

fn squareIndex(file: usize, rank: usize) u8 {
    return @intCast(rank * 8 + file);
}

fn evaluatePassedPawns(board: *ZChess.Board) i32 {
    _ = board; // TODO: Implement passed pawn evaluation bitboard logic
    return 0;
}

fn evaluateCenterPawnPresence(board: *ZChess.Board, color: ZChess.Color) i32 {
    var bonus: i32 = 0;

    const home_rank: usize = if (color == .White) 1 else 6;
    const near_center_rank: usize = if (color == .White) 2 else 5;
    const center_rank: usize = if (color == .White) 3 else 4;
    const advanced_center_rank: usize = if (color == .White) 4 else 3;

    const bb = board.getPieceBitboard(.Pawn, color);

    const centerFiles: [3]usize = .{ 2, 3, 4 };

    for (centerFiles) |file| {
        if ((bb & (@as(u64, 1) << @intCast(squareIndex(file, home_rank)))) != 0) {
            bonus += 10; // Pawn on home rank center file
        }
        if ((bb & (@as(u64, 1) << @intCast(squareIndex(file, near_center_rank))) != 0)) {
            bonus += 20; // Pawn on near center rank
        }
        if ((bb & (@as(u64, 1) << @intCast(squareIndex(file, center_rank))) != 0)) {
            bonus += 40; // Pawn on center rank
        }
        if ((bb & (@as(u64, 1) << @intCast(squareIndex(file, advanced_center_rank))) != 0)) {
            bonus += 30; // Pawn on advanced center rank
        }
    }

    return bonus;
}

fn evaluateOpeningCenterControl(board: *ZChess.Board) i32 {
    return evaluateCenterPawnPresence(board, .White) - evaluateCenterPawnPresence(board, .Black);
}

fn evaluatePieceScore(board: *ZChess.Board) i32 {
    var score: i32 = 0;

    inline for (ptypes_all) |ptype| {
        var bb = board.getPieceBitboard(ptype, .White);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;

            // More valuable piece = better eval
            score += pieceValues[@intFromEnum(ptype)];
            // Better position = better eval (xor due to inverted piece tables)
            score += pieceSquareValue(ptype, board, sq ^ 56);
            // Sees more squares = better eval
            score += @divFloor(@popCount(board.moveGen.getPossibleAttacksBitboard(board, .White)), 10);
        }

        bb = board.getPieceBitboard(ptype, .Black);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;

            // More valuable piece = better eval
            score -= pieceValues[@intFromEnum(ptype)];
            // Better position = better eval
            score -= pieceSquareValue(ptype, board, sq);
            // Sees more squares = better eval
            score -= @divFloor(@popCount(board.moveGen.getPossibleAttacksBitboard(board, .Black)), 10);
        }
    }

    return score;
}

inline fn toRel(val: i32, color: ZChess.Color) i32 {
    return if (color == .White) val else -val;
}

fn pieceSquareValue(ptype: ZChess.PieceType, board: *ZChess.Board, sq: usize) i32 {
    return switch (ptype) {
        .Pawn => PST.pawnTable[sq],
        .Knight => PST.knightTable[sq],
        .Bishop => PST.bishopTable[sq],
        .Rook => PST.rookTable[sq],
        .Queen => PST.queenTable[sq],
        .King => blk: {
            if (isEndgame(board)) {
                break :blk PST.kingEndTable[sq];
            } else {
                break :blk PST.kingMidTable[sq];
            }
        },
    };
}

fn squareFromBitboard(b: u64) ZChess.Square {
    std.debug.assert(b != 0);
    return ZChess.Square.fromFlat(@intCast(@ctz(b)));
}

fn endgameEvaluation(board: *ZChess.Board) i32 {
    // Simple endgame evaluation.
    // 1. Want king close to other king so can help with mates

    var score: i32 = 0;

    const whiteKing = squareFromBitboard(board.getPieceBitboard(.King, .White));
    const blackKing = squareFromBitboard(board.getPieceBitboard(.King, .Black));

    // Manhattan distance
    const dist: i32 = @abs(whiteKing.file - blackKing.file) + @abs(whiteKing.rank - blackKing.rank);

    // This div 4 is vibes based. Do not trust it
    if (board.turn == .White)
        score += @divFloor(16 - dist, 4);
    if (board.turn == .Black)
        score -= @divFloor(16 - dist, 4);

    return score;
}

fn calculateColorMaterial(board: *ZChess.Board, color: ZChess.Color) i32 {
    var total: i32 = 0;
    inline for (ptypes) |ptype| {
        const count = @popCount(board.getPieceBitboard(ptype, color));
        total += count * pieceValues[@intFromEnum(ptype)];
    }
    return total;
}

fn isEndgame(board: *ZChess.Board) bool {
    const whiteMaterial = calculateColorMaterial(board, .White);
    const blackMaterial = calculateColorMaterial(board, .Black);
    return (whiteMaterial <= 1300) or (blackMaterial <= 1300); // Simple threshold for endgame, can be refined
}

pub fn evaluateBoard(board: *ZChess.Board, color: ZChess.Color) i32 {
    var score = evaluatePieceScore(board);
    score += evaluateOpeningCenterControl(board);
    score += evaluatePassedPawns(board);

    if (isEndgame(board)) {
        score += endgameEvaluation(board);
    }

    return toRel(score, color);
}

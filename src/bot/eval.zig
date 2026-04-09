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

fn squareIndex(file: usize, rank: usize) u8 {
    return @intCast(rank * 8 + file);
}

fn evaluatePassedPawns(board: *ZChess.Board) i32 {
    _ = board; // TODO: Implement passed pawn evaluation logic
    return 0;
}

fn evaluateCenterPawnPresence(board: *ZChess.Board, color: ZChess.Color) i32 {
    var bonus: i32 = 0;

    const home_rank: usize = if (color == .White) 1 else 6;
    const near_center_rank: usize = if (color == .White) 2 else 5;
    const center_rank: usize = if (color == .White) 3 else 4;
    const advanced_center_rank: usize = if (color == .White) 4 else 3;

    const bb = board.getPieceBitboard(.Pawn, color);

    const centerFiles: [3]usize = .{ 3, 4, 5 };

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

    inline for (ptypes) |ptype| {
        var bb = board.getPieceBitboard(ptype, .White);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;
            score += pieceValues[@intFromEnum(ptype)] + pieceSquareValue(ptype, board, sq);
        }

        bb = board.getPieceBitboard(ptype, .Black);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;
            const mirroredSq = (7 - (sq / 8)) * 8 + (sq % 8);
            score -= pieceValues[@intFromEnum(ptype)] + pieceSquareValue(ptype, board, mirroredSq);
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

fn endgameEvaluation(board: *ZChess.Board) i32 {
    _ = board; // Placeholder for future endgame-specific evaluation logic
    return 0;
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

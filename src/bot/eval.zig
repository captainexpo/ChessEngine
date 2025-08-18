const std = @import("std");
const ZChess = @import("zchess");
const PST = @import("squaretables.zig");

pub const MATE_VALUE: i32 = 32000;
pub const MATE_THRESHOLD: i32 = 31000; // Threshold for checkmate evaluation

const pieceValues = [_]i32{
    100, // Pawn
    320, // Knight
    330, // Bishop
    500, // Rook
    900, // Queen
    20000, // King (not used in evaluation)
};

const ptypes = [_]ZChess.PieceType{
    .Pawn,
    .Knight,
    .Bishop,
    .Rook,
    .Queen,
};

fn evaluatePieceScore(board: *ZChess.Board) i32 {
    var score: i32 = 0;

    inline for (ptypes) |ptype| {
        var bb = board.getPieceBitboard(ptype, .White);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;
            score += pieceValues[@intFromEnum(ptype)] + pieceSquareValue(ptype, sq);
        }

        bb = board.getPieceBitboard(ptype, .Black);
        while (bb != 0) {
            const sq = @ctz(bb);
            bb &= bb - 1;
            const mirroredSq = (7 - (sq / 8)) * 8 + (sq % 8);
            score -= pieceValues[@intFromEnum(ptype)] + pieceSquareValue(ptype, mirroredSq);
        }
    }

    return score;
}

inline fn toRel(val: i32, color: ZChess.Color) i32 {
    return if (color == .White) val else -val;
}

fn movementScore(board: *ZChess.Board) i32 {
    const moves = board.getPossibleMoves() catch unreachable;

    // White’s mobility contributes positively, Black’s negatively
    var score: i32 = 0;
    if (board.turn == .White) {
        score += @intCast(moves.len);
    } else {
        score -= @intCast(moves.len);
    }
    return score * 10;
}

fn pieceSquareValue(ptype: ZChess.PieceType, sq: usize) i32 {
    return switch (ptype) {
        .Pawn => PST.pawnTable[sq],
        .Knight => PST.knightTable[sq],
        .Bishop => PST.bishopTable[sq],
        .Rook => PST.rookTable[sq],
        .Queen => PST.queenTable[sq],
        .King => PST.kingTable[sq],
    };
}

fn evaluateCheckmateScore(board: *ZChess.Board) i32 {
    if (board.isInCheckmate() catch return 0) {
        // If the side to move is checkmated, that’s good for the other side
        return if (board.turn == .White) -MATE_VALUE else MATE_VALUE;
    }
    return 0;
}

pub fn evaluateBoard(board: *ZChess.Board, color: ZChess.Color) i32 {
    var score = evaluateCheckmateScore(board);
    if (score == 0) {
        score = evaluatePieceScore(board);
        score += movementScore(board);
    }
    return toRel(score, color);
}

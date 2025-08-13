const std = @import("std");
const ZChess = @import("zchess");
const PST = @import("squaretables.zig");
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

fn movementScore(board: *ZChess.Board) i32 {
    const moves = board.moveGen.generateMoves(std.heap.page_allocator, board, board.turn, .{ .get_pseudo_legal = true }) catch return 0;
    defer std.heap.page_allocator.free(moves.moves);
    return @as(i32, @intCast(moves.moves.len)) * @as(i32, if (board.turn == .White) 10 else -10);
}
fn pieceSquareValue(ptype: ZChess.PieceType, sq: usize) i32 {
    // Select PST for piece type and return value for square.
    // Example:
    return switch (ptype) {
        .Pawn => PST.pawnTable[sq],
        .Knight => PST.knightTable[sq],
        .Bishop => PST.bishopTable[sq],
        .Rook => PST.rookTable[sq],
        .Queen => PST.queenTable[sq],
        .King => PST.kingTable[sq],
    };
}

pub fn evaluateBoard(board: *ZChess.Board, color: ZChess.Color) i32 {
    var score = evaluatePieceScore(board);
    score += evaluateCheckmateScore(board);
    score += movementScore(board);
    return score * if (color == .White) @as(i32, 1) else @as(i32, -1);
}

fn evaluateCheckmateScore(board: *ZChess.Board) i32 {
    if (board.isInCheckmate) {
        if (board.turn == .Black) {
            return 100000;
        } else {
            return -100000;
        }
    }
    return 0;
}

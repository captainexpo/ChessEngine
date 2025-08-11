const std = @import("std");
const ZChess = @import("zchess");

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
        score += @as(i32, @popCount(board.getPieceBitboard(ptype, .White))) * pieceValues[@intFromEnum(ptype)];
        score -= @as(i32, @popCount(board.getPieceBitboard(ptype, .Black))) * pieceValues[@intFromEnum(ptype)];
    }
    return score;
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

pub fn evaluateBoard(board: *ZChess.Board, color: ZChess.Color) i32 {
    var score: i32 = 0;

    score += evaluatePieceScore(board);
    score += evaluateCheckmateScore(board);

    return score * if (color == .White) @as(i32, 1) else @as(i32, -1);
}

const std = @import("std");
const RandGen = std.Random.DefaultPrng;

const ZChess = @import("zchess");

const Eval = @import("eval.zig");

pub const ChessBot = struct {
    allocator: std.mem.Allocator,

    pub fn init(self: *ChessBot, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
    }

    pub fn getMove(self: *ChessBot, board: *ZChess.Board) !ZChess.Move {
        const moves = board.possibleMoves;

        var rng = RandGen.init(@intCast(std.time.microTimestamp()));
        var moveToPlay = moves[rng.next() % moves.len];

        var bestScore: i32 = std.math.minInt(i32);

        for (moves) |move| {
            const undo = board.makeMove(move) catch continue;
            const score = -self.negaMax(board, 5);
            board.undoMove(undo) catch continue;
            if (score > bestScore) {
                bestScore = score;
                moveToPlay = move;
            }
        }

        return moveToPlay;
    }
    fn negaMax(self: *ChessBot, board: *ZChess.Board, depth: i32) i32 {
        if (depth == 0) return Eval.evaluateBoard(board, board.turn);
        var max: i32 = std.math.minInt(i32);
        for (board.possibleMoves) |move| {
            const undo = board.makeMove(move) catch continue;
            const score = -self.negaMax(board, depth - 1);
            board.undoMove(undo) catch continue;
            if (score > max)
                max = score;
        }
        return max;
    }
};

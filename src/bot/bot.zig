const std = @import("std");
const ZChess = @import("zchess");

const RandGen = std.Random.DefaultPrng;

pub const ChessBot = struct {
    allocator: std.mem.Allocator,
    rng: RandGen = undefined,
    pub fn init(self: *ChessBot, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.rng = RandGen.init(0);
    }

    pub fn getMove(self: *ChessBot, board: *ZChess.Board) !ZChess.Move {
        const possible_moves = board.possibleMoves;
        _ = self;
        return possible_moves[0];
    }
};

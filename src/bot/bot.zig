const std = @import("std");
const ZChess = @import("zchess");

pub const ChessBot = struct {
    allocator: std.mem.Allocator,

    pub fn init(self: *ChessBot, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
    }

    pub fn getMove(self: *ChessBot, board: *ZChess.Board) !ZChess.Move {
        _ = self;
        const possible_moves = board.possibleMoves;
        return possible_moves[0];
    }
};

const std = @import("std");
const RandGen = std.Random.DefaultPrng;

const ZChess = @import("zchess");

const Eval = @import("eval.zig");
const UCI = @import("../uci.zig").UCI;

const NEG_INF = std.math.minInt(i32) + 1;
const POS_INF = std.math.maxInt(i32);

pub const ChessBot = struct {
    allocator: std.mem.Allocator,
    uci_interface: *UCI,

    nodes: u64 = 0,

    pub fn init(self: *ChessBot, allocator: std.mem.Allocator, interface: *UCI) void {
        self.allocator = allocator;
        self.uci_interface = interface;
    }

    fn writeError(self: *ChessBot, comptime fmt: []const u8, args: anytype) void {
        self.uci_interface.startInfo();
        self.uci_interface.writeInfo(.String, fmt, args);
        self.uci_interface.endInfo();
    }

    pub fn getMove(self: *ChessBot, board: *ZChess.Board) !ZChess.Move {
        self.nodes = 0;
        const moves = try board.getPossibleMoves(self.allocator);
        defer self.allocator.free(moves);

        var rng = RandGen.init(@intCast(std.time.microTimestamp()));
        var moveToPlay = moves[rng.next() % moves.len];

        var bestScore: i32 = std.math.minInt(i32);

        for (moves) |move| {
            const undo = board.makeMove(move) catch continue;
            const score = -self.negaMax(
                self.allocator,
                board,
                @as(i32, 3),
                NEG_INF,
                POS_INF,
            );

            self.uci_interface.startInfo();
            self.uci_interface.writeInfo(.Depth, "{d}", .{3});
            self.uci_interface.writeInfo(.Score_cp, "{d}", .{score});
            self.uci_interface.writeInfo(.Pv, "{s}", .{move.toString(self.allocator) catch "??"});
            self.uci_interface.writeInfo(.Nodes, "{d}", .{self.nodes});
            self.uci_interface.endInfo();

            board.undoMove(undo) catch continue;
            if (score > bestScore) {
                bestScore = score;
                moveToPlay = move;
            }
        }

        return moveToPlay;
    }
    fn negaMax(self: *ChessBot, allocator: std.mem.Allocator, board: *ZChess.Board, depth: i32, alpha: i32, beta: i32) i32 {
        self.nodes += 1;
        if (depth <= 0) return Eval.evaluateBoard(board, board.turn);
        var max: i32 = std.math.minInt(i32);
        var alphaLocal = alpha;
        const moves = board.getPossibleMoves(allocator) catch |err| {
            self.writeError("Failed to get possible moves ({!})", .{err});
            return max;
        };
        defer allocator.free(moves);
        for (moves) |move| {
            const undo = board.makeMove(move) catch |err| {
                self.writeError("Failed to make move ({!})", .{err});
                continue;
            };
            const score = -self.negaMax(allocator, board, depth - 1, -beta, -alpha);
            board.undoMove(undo) catch |err| {
                self.writeError("Failed to undo move ({!})", .{err});
                continue;
            };
            if (score > max) max = score;
            if (score > alphaLocal) alphaLocal = score;
            if (alphaLocal >= beta) break; // cut-off

        }
        return max;
    }
};

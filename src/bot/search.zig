const ChessBot = @import("bot.zig").ChessBot;
const ZChess = @import("zchess");
const Eval = @import("eval.zig");
const std = @import("std");

const TTEntry = struct {
    key: u64, // position hash
    move: ZChess.Move, // best move found
    score: i16, // eval
    depth: i8, // depth of search
    flag: u8, // bound type
};

pub const Search = struct {
    transpositionTable: []TTEntry,
    ttableSize: usize,
    allocator: std.mem.Allocator,

    pub fn orderMoves(moves: []ZChess.Move, _: *ZChess.Board) void {
        std.sort.heap(ZChess.Move, moves, {}, struct {
            fn lessThan(_: void, lhs: ZChess.Move, rhs: ZChess.Move) bool {
                // Checks > Promotion > Captures > Non-captures
                var lhs_score: i32 = 0;
                var rhs_score: i32 = 0;
                const lhs_is_cap = (lhs.move_type == .Capture) or
                    (lhs.move_type == .EnPassant);
                const rhs_is_cap = (rhs.move_type == .Capture) or
                    (rhs.move_type == .EnPassant);

                if (lhs_is_cap)
                    lhs_score += 1000;
                if (rhs_is_cap)
                    rhs_score += 1000;

                if (lhs.promotion_piecetype != null)
                    lhs_score += 100;
                if (rhs.promotion_piecetype != null)
                    rhs_score += 100;

                return lhs_score > rhs_score;
            }
        }.lessThan);
    }

    pub fn init(allocator: std.mem.Allocator, size: usize) !Search {
        const table = try allocator.alloc(TTEntry, size);
        // Optional: zero-initialize
        for (table) |*entry| {
            entry.* = TTEntry{
                .key = 0,
                .move = undefined,
                .score = 0,
                .depth = -128,
                .flag = 0,
            };
        }
        return Search{
            .transpositionTable = table,
            .ttableSize = size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Search) void {
        self.allocator.free(self.transpositionTable);
    }

    fn probeTT(self: *Search, key: u64, depth: i32, alpha: i32, beta: i32) ?i32 {
        const index: usize = key & (@as(u64, @intCast(self.ttableSize - 1)));
        const entry = self.transpositionTable[index];
        if (entry.key == key and entry.depth >= depth) {
            switch (entry.flag) {
                0 => return entry.score, // exact
                1 => if (entry.score <= alpha) return alpha, // alpha bound
                2 => if (entry.score >= beta) return beta, // beta bound
                else => {},
            }
        }
        return null;
    }
    fn storeTT(self: *Search, key: u64, score: i32, depth: i32, flag: u8, best_move: ZChess.Move) void {
        const index: usize = key & (@as(u64, @intCast(self.ttableSize - 1)));
        self.transpositionTable[index] = TTEntry{
            .key = key,
            .move = best_move,
            .score = @intCast(score),
            .depth = @intCast(depth),
            .flag = flag,
        };
    }
    pub fn negaMax(
        self: *Search,
        chessBot: *ChessBot,
        allocator: std.mem.Allocator,
        board: *ZChess.Board,
        depth: i32,
        depth_extend: i32,
        alpha: i32,
        beta: i32,
    ) i32 {
        chessBot.nodes += 1;
        const zobrist = board.getZobristHash();

        // TT probe before searching
        if (depth > 0) {
            if (self.probeTT(zobrist, depth, alpha, beta)) |cached| {
                return cached;
            }
        }

        if ((depth + @min(depth_extend, 3)) <= 0) {
            const eval = Eval.evaluateBoard(board, board.turn);
            const otherEval = Eval.evaluateBoard(board, board.turn.opposite());
            std.debug.print("Eval: {d} vs {d}\n", .{ eval, otherEval });
            self.storeTT(zobrist, eval, depth, 0, undefined);
            return eval;
        }

        var max: i32 = std.math.minInt(i32);
        var alphaLocal = alpha;
        var bestMove: ZChess.Move = undefined;

        const moves = board.getPossibleMoves(allocator) catch |err| {
            chessBot.writeError("Failed to get possible moves ({!})", .{err});
            return max;
        };
        defer allocator.free(moves);
        orderMoves(moves, board);
        for (moves, 0..moves.len) |move, _| {
            const undo = board.makeMove(move) catch |err| {
                chessBot.writeError("Failed to make move ({!})", .{err});
                continue;
            };

            const orderExtension: i32 = 0; // Extend search for first few moves
            const score = -self.negaMax(chessBot, allocator, board, depth - 1, depth_extend + orderExtension, -beta, -alphaLocal);

            board.undoMove(undo) catch |err| {
                chessBot.writeError("Failed to undo move ({!})", .{err});
                continue;
            };

            if (score > max) {
                max = score;
                bestMove = move; // Assuming you have such a method
            }
            if (score > alphaLocal) alphaLocal = score;
            if (alphaLocal >= beta) {
                break;
            } // cutoff
        }

        // Determine bound type for storage
        var flag: u8 = 0; // exact
        if (max <= alpha) flag = 1 // alpha bound
        else if (max >= beta) flag = 2; // beta bound

        self.storeTT(zobrist, max, depth, flag, bestMove);

        return max;
    }
};

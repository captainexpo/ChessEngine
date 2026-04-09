const std = @import("std");
const ZChess = @import("zchess");
const UCI = @import("../uci.zig").UCI;
const Eval = @import("eval.zig");
const Search = @import("search.zig");

const NEG_INF = std.math.minInt(i32) + 1;
const POS_INF = std.math.maxInt(i32);

pub const ChessBot = struct {
    allocator: std.mem.Allocator,
    uci_interface: *UCI,
    search: Search.Search = undefined,
    nodes: u64 = 0,

    defaultDepth: i32 = 7,
    maxDepth: i32 = 8,

    pub fn new(allocator: std.mem.Allocator, interface: *UCI) ChessBot {
        var self = ChessBot{
            .allocator = allocator,
            .uci_interface = interface,
        };

        self.search = Search.Search.init(allocator, 1 << 20) catch |err| {
            self.writeError("Failed to initialize search: {}", .{err});
            std.process.exit(1);
        };

        return self;
    }

    pub fn writeError(self: *ChessBot, comptime fmt: []const u8, args: anytype) void {
        self.uci_interface.startInfo();
        self.uci_interface.writeInfo(.String, fmt, args);
        self.uci_interface.endInfo();
    }

    pub fn reportSearchInfo(self: *ChessBot, board: *ZChess.Board, depth: i32, bestScore: i32, moveToPlay: ZChess.Move) !void {
        const moveStr = try moveToPlay.toString(self.allocator);
        defer self.allocator.free(moveStr);

        self.uci_interface.startInfo();
        self.uci_interface.writeInfo(.Depth, "{d}", .{depth});

        const score_is_mate = @abs(bestScore) > Eval.MATE_THRESHOLD;
        if (score_is_mate) {
            const raw_mate = Eval.MATE_VALUE - @as(i32, @intCast(@abs(bestScore)));
            const mate_in: i32 = @max(raw_mate, @as(i32, 1));
            const signed_mate: i32 = if (bestScore < 0) -mate_in else mate_in;
            self.uci_interface.writeInfo(.Score_mate, "{d}", .{signed_mate});
        } else {
            self.uci_interface.writeInfo(.Score_cp, "{d}", .{bestScore});
        }

        self.uci_interface.writeInfo(.Pv, "{s}", .{moveStr});
        self.uci_interface.writeInfo(.Nodes, "{d}", .{self.nodes});
        self.uci_interface.endInfo();

        _ = board;
    }

    pub fn getMoveWithLimits(self: *ChessBot, board: *ZChess.Board, time_budget_ms: i64, requested_depth: ?i32) !ZChess.Move {
        self.nodes = 0;
        const moves = try board.getPossibleMoves();
        if (moves.len == 0) return error.NoLegalMoves;

        const root_moves = try self.allocator.dupe(ZChess.Move, moves);
        defer self.allocator.free(root_moves);

        var moveToPlay = root_moves[0];

        const started_ms = std.time.milliTimestamp();
        const depth_target = @min(requested_depth orelse self.defaultDepth, self.maxDepth);

        var bestScore: i32 = 0;
        var completed_depth: i32 = 0;
        var pvMove: ?ZChess.Move = null;

        var depth: i32 = 1;
        while (depth <= depth_target) : (depth += 1) {
            if (time_budget_ms > 0 and (std.time.milliTimestamp() - started_ms) >= time_budget_ms and completed_depth > 0) break;

            var aspiration_window: i32 = if (depth == 1) 0 else 30;
            var alpha = if (depth == 1) NEG_INF else bestScore - aspiration_window;
            var beta = if (depth == 1) POS_INF else bestScore + aspiration_window;
            var iter_best_score: i32 = NEG_INF;
            var iter_best_move: ?ZChess.Move = null;

            while (true) {
                const result = self.search.searchRoot(self, self.allocator, board, depth, alpha, beta, pvMove);
                iter_best_score = result.score;
                iter_best_move = result.best_move;

                if (iter_best_score <= alpha) {
                    if (time_budget_ms > 0 and (std.time.milliTimestamp() - started_ms) >= time_budget_ms) break;
                    aspiration_window *= 2;
                    alpha = @max(NEG_INF, bestScore - aspiration_window);
                    beta = bestScore + aspiration_window;
                    continue;
                }

                if (iter_best_score >= beta) {
                    if (time_budget_ms > 0 and (std.time.milliTimestamp() - started_ms) >= time_budget_ms) break;
                    aspiration_window *= 2;
                    alpha = bestScore - aspiration_window;
                    beta = @min(POS_INF, bestScore + aspiration_window);
                    continue;
                }

                break;
            }

            if (iter_best_move == null) break;

            bestScore = iter_best_score;
            moveToPlay = iter_best_move.?;
            pvMove = iter_best_move;
            completed_depth = depth;

            if (root_moves.len > 0) {
                var best_index: ?usize = null;
                for (root_moves, 0..) |candidate, index| {
                    if (candidate.from_square.toFlat() == moveToPlay.from_square.toFlat() and
                        candidate.to_square.toFlat() == moveToPlay.to_square.toFlat() and
                        candidate.promotion_piecetype == moveToPlay.promotion_piecetype and
                        candidate.move_type == moveToPlay.move_type)
                    {
                        best_index = index;
                        break;
                    }
                }
                if (best_index) |idx| {
                    if (idx != 0) {
                        const tmp = root_moves[0];
                        root_moves[0] = root_moves[idx];
                        root_moves[idx] = tmp;
                    }
                }
            }
        }

        if (completed_depth == 0) completed_depth = 1;
        _ = self.reportSearchInfo(board, completed_depth, bestScore, moveToPlay) catch {};

        return moveToPlay;
    }

    pub fn getMove(self: *ChessBot, board: *ZChess.Board) !ZChess.Move {
        if (board.fullMoveNumber == 1 and board.turn == ZChess.Color.White) {
            const e4 = ZChess.Move{
                .from_square = ZChess.Square.fromFlat(12),
                .to_square = ZChess.Square.fromFlat(28),
                .move_type = ZChess.MoveType.Normal,
                .promotion_piecetype = null,
            };
            return e4;
        }
        return self.getMoveWithLimits(board, 0, null);
    }

    pub fn deinit(self: *ChessBot) void {
        self.search.deinit();
    }
};

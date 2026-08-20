const std = @import("std");
const ZChess = @import("zchess");
const Eval = @import("eval.zig");
const ChessBot = @import("bot.zig").ChessBot;

const TTEntry = struct {
    key: u64,
    move: ?ZChess.Move,
    score: i32,
    depth: i8,
    flag: u8,
};

pub const SearchResult = struct {
    score: i32,
    best_move: ?ZChess.Move,
};

const CapturePieceValues = [_]i32{ 100, 320, 330, 500, 900, 20000 };
const MAX_PLY: usize = 128;
const KILLER_SLOTS: usize = 2;

fn plyIndex(ply: i32) usize {
    if (ply <= 0) return 0;
    const uply: usize = @intCast(ply);
    return if (uply < MAX_PLY) uply else MAX_PLY - 1;
}

fn colorIndex(color: ZChess.Color) usize {
    return if (color == .White) 0 else 1;
}

fn pieceValue(piece_type: ZChess.PieceType) i32 {
    return CapturePieceValues[@intFromEnum(piece_type)];
}

fn eqlMove(a: ZChess.Move, b: ZChess.Move) bool {
    return a.from_square.toFlat() == b.from_square.toFlat() and
        a.to_square.toFlat() == b.to_square.toFlat() and
        a.promotion_piecetype == b.promotion_piecetype and
        a.move_type == b.move_type;
}

pub const Search = struct {
    transpositionTable: []TTEntry,
    ttableSize: usize,
    allocator: std.mem.Allocator,
    killers: [MAX_PLY][KILLER_SLOTS]?ZChess.Move,
    history: [2][6][64]i32,

    fn scoreMove(self: *Search, board: *ZChess.Board, move: ZChess.Move, hashMove: ?ZChess.Move, ply: usize) i32 {
        if (hashMove) |hm| {
            if (eqlMove(move, hm)) return 1000000;
        }

        var score: i32 = 0;

        if (ply < MAX_PLY) {
            if (self.killers[ply][0]) |killer| {
                if (eqlMove(move, killer)) return 900000;
            }
            if (self.killers[ply][1]) |killer| {
                if (eqlMove(move, killer)) return 800000;
            }
        }

        if (move.promotion_piecetype) |promo| {
            score += 100000 + pieceValue(promo);
        }

        if (move.move_type == .Castle) {
            score += 1000;
        }

        if (move.isCapture()) {
            const attacker = board.getPiece(move.from_square.toFlat());
            const victim = board.getPiece(move.to_square.toFlat());
            const attacker_value = if (attacker) |p| pieceValue(p.getType()) else 0;
            const victim_value = if (victim) |p| pieceValue(p.getType()) else 100;
            score += 50000 + victim_value * 10 - attacker_value;
        } else if (board.getPiece(move.from_square.toFlat())) |piece| {
            const c_idx = colorIndex(piece.getColor());
            const p_idx = @intFromEnum(piece.getType());
            const to_sq = move.to_square.toFlat();
            score += self.history[c_idx][p_idx][to_sq];
        }

        return score;
    }

    fn addKiller(self: *Search, ply: usize, move: ZChess.Move) void {
        if (ply >= MAX_PLY) return;

        if (self.killers[ply][0]) |k0| {
            if (eqlMove(k0, move)) return;
        }

        self.killers[ply][1] = self.killers[ply][0];
        self.killers[ply][0] = move;
    }

    fn addHistory(self: *Search, board: *ZChess.Board, side_to_move: ZChess.Color, move: ZChess.Move, depth: i32) void {
        const piece = board.getPiece(move.from_square.toFlat()) orelse return;
        const c_idx = colorIndex(side_to_move);
        const p_idx = @intFromEnum(piece.getType());
        const to_sq = move.to_square.toFlat();
        const bonus = depth * depth;
        const current = self.history[c_idx][p_idx][to_sq];
        self.history[c_idx][p_idx][to_sq] = @min(1_000_000, current + bonus);
    }

    const ScoredMove = struct { move: ZChess.Move, score: i32 };

    pub fn orderMoves(self: *Search, moves: []ZChess.Move, board: *ZChess.Board, hashMove: ?ZChess.Move, ply: usize) void {
        if (moves.len <= 1) return;

        var buf: [256]ScoredMove = undefined;
        const scored = buf[0..moves.len];
        for (moves, 0..) |move, i| {
            scored[i] = .{ .move = move, .score = self.scoreMove(board, move, hashMove, ply) };
        }

        const lessThan = struct {
            fn lessThan(_: void, lhs: ScoredMove, rhs: ScoredMove) bool {
                return lhs.score > rhs.score;
            }
        }.lessThan;

        std.sort.pdq(ScoredMove, scored, {}, lessThan);

        for (scored, 0..) |sm, i| {
            moves[i] = sm.move;
        }
    }

    pub fn init(allocator: std.mem.Allocator, size: usize) !Search {
        const table = try allocator.alloc(TTEntry, size);
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
            .killers = [_][KILLER_SLOTS]?ZChess.Move{[_]?ZChess.Move{ null, null }} ** MAX_PLY,
            .history = [_][6][64]i32{[_][64]i32{[_]i32{0} ** 64} ** 6} ** 2,
        };
    }

    pub fn deinit(self: *Search) void {
        self.allocator.free(self.transpositionTable);
    }

    fn probeTTEntry(self: *Search, key: u64, depth: i32) ?TTEntry {
        const index: usize = key & (@as(u64, @intCast(self.ttableSize - 1)));
        const entry = self.transpositionTable[index];
        if (entry.key == key and entry.depth >= depth) {
            return entry;
        }
        return null;
    }

    fn probeTT(self: *Search, key: u64, depth: i32, alpha: i32, beta: i32) ?i32 {
        const index: usize = key & (@as(u64, @intCast(self.ttableSize - 1)));
        const entry = self.transpositionTable[index];
        if (entry.key == key and entry.depth >= depth) {
            switch (entry.flag) {
                0 => return entry.score,
                1 => if (entry.score <= alpha) return alpha,
                2 => if (entry.score >= beta) return beta,
                else => {},
            }
        }
        return null;
    }

    fn storeTT(self: *Search, key: u64, score: i32, depth: i32, flag: u8, best_move: ?ZChess.Move) void {
        const index: usize = key & (@as(u64, @intCast(self.ttableSize - 1)));
        self.transpositionTable[index] = TTEntry{
            .key = key,
            .move = best_move,
            .score = score,
            .depth = @intCast(depth),
            .flag = flag,
        };
    }

    fn quiescence(
        self: *Search,
        chessBot: *ChessBot,
        allocator: std.mem.Allocator,
        board: *ZChess.Board,
        alpha: i32,
        beta: i32,
        ply: i32,
    ) i32 {
        chessBot.nodes += 1;

        const moves = board.getPossibleMoves() catch {
            return Eval.evaluateBoard(board, board.turn);
        };

        if (moves.len == 0) {
            return if (board.isInCheck() catch false) -Eval.MATE_VALUE + ply else 0;
        }

        const in_check = board.isInCheck() catch false;
        const stand_pat = Eval.evaluateBoard(board, board.turn);

        var alphaLocal = alpha;
        if (!in_check) {
            if (stand_pat >= beta) return beta;
            if (stand_pat > alphaLocal) alphaLocal = stand_pat;
        } else {
            if (stand_pat > alphaLocal) alphaLocal = stand_pat;
        }

        var noisy_buf: [256]ZChess.Move = undefined;
        var noisy_len: usize = 0;
        for (moves) |move| {
            if (in_check or move.isCapture() or move.promotion_piecetype != null) {
                if (noisy_len < noisy_buf.len) {
                    noisy_buf[noisy_len] = move;
                    noisy_len += 1;
                }
            }
        }
        const noisy_moves = noisy_buf[0..noisy_len];

        self.orderMoves(noisy_moves, board, null, plyIndex(ply));
        for (noisy_moves) |move| {
            const undo = board.makeMove(move) catch continue;
            const score = -self.quiescence(chessBot, allocator, board, -beta, -alphaLocal, ply + 1);
            board.undoMove(undo) catch continue;

            if (score >= beta) return beta;
            if (score > alphaLocal) alphaLocal = score;
        }

        return alphaLocal;
    }

    fn normalizeMateScore(score: i32, ply: i32) i32 {
        if (score > Eval.MATE_THRESHOLD) return score + ply;
        if (score < -Eval.MATE_THRESHOLD) return score - ply;
        return score;
    }

    fn denormalizeMateScore(score: i32, ply: i32) i32 {
        if (score > Eval.MATE_THRESHOLD) return score - ply;
        if (score < -Eval.MATE_THRESHOLD) return score + ply;
        return score;
    }

    fn searchNode(
        self: *Search,
        chessBot: *ChessBot,
        allocator: std.mem.Allocator,
        board: *ZChess.Board,
        depth: i32,
        alpha: i32,
        beta: i32,
        ply: i32,
    ) i32 {
        chessBot.nodes += 1;
        const zobrist = board.getZobristHash();

        if (board.isInStalemate() catch false) {
            return @divTrunc(Eval.evaluateBoard(board, board.turn), 8);
        }

        if (depth <= 0) {
            return self.quiescence(chessBot, allocator, board, alpha, beta, ply);
        }

        if (self.probeTT(zobrist, depth, alpha, beta)) |cached| {
            return denormalizeMateScore(cached, ply);
        }

        var max: i32 = -Eval.MATE_VALUE * 2;
        var alphaLocal = alpha;
        var bestMove: ?ZChess.Move = null;
        const node_in_check = board.isInCheck() catch false;
        const side_to_move = board.turn;

        const moves = board.getPossibleMoves() catch |err| {
            chessBot.writeError("Failed to get possible moves ({})", .{err});
            return max;
        };

        if (moves.len == 0) {
            return if (board.isInCheck() catch false) -Eval.MATE_VALUE + ply else 0;
        }

        var local_moves: [256]ZChess.Move = undefined;
1 reply
        var heap_moves: ?[]ZChess.Move = null;
        defer if (heap_moves) |hm| allocator.free(hm);

        const tt_move = if (self.probeTTEntry(zobrist, depth)) |entry| entry.move else null;

        const ordered_moves = blk: {
            if (moves.len <= local_moves.len) {
                @memcpy(local_moves[0..moves.len], moves);
                break :blk local_moves[0..moves.len];
            }

            const hm = allocator.dupe(ZChess.Move, moves) catch {
                chessBot.writeError("Failed to copy moves for search", .{});
                return max;
            };
            heap_moves = hm;
            break :blk hm;
        };

        self.orderMoves(ordered_moves, board, tt_move, plyIndex(ply));
        for (ordered_moves, 0..) |move, move_index| {
            const undo = board.makeMove(move) catch |err| {
                chessBot.writeError("Failed to make move ({})", .{err});
                return max;
            };

            var newDepth = depth - 1;
            if (node_in_check) newDepth += 1;

            // const captureMoves = board.getCaptureMoves(allocator) catch |err|{
            //     chessBot.writeError("Failed to get capture moves ({})", .{err});
            //     return max;
            // };
            // defer allocator.free(captureMoves);
            //
            // if (captureMoves.len != 0) {
            //     newDepth += 1;
            // }
            // if (ordered_moves.len <= 5) newDepth += 1;
            // if (move.promotion_piecetype != null) newDepth += 1;
            if (newDepth > depth) newDepth = depth;

            var search_depth = newDepth;
            const is_quiet = !move.isCapture() and move.promotion_piecetype == null and move.move_type != .Castle;
            if (!node_in_check and is_quiet and depth >= 3 and move_index >= 3 and search_depth > 1) {
                search_depth -= 1;
            }
            if (!node_in_check and is_quiet and depth >= 5 and move_index >= 8 and search_depth > 2) {
                search_depth -= 1;
            }

            var score = -self.searchNode(chessBot, allocator, board, search_depth, -beta, -alphaLocal, ply + 1);
            if (search_depth < newDepth and score > alphaLocal) {
                score = -self.searchNode(chessBot, allocator, board, newDepth, -beta, -alphaLocal, ply + 1);
            }

            board.undoMove(undo) catch |err| {
                chessBot.writeError("Failed to undo move ({})", .{err});
                continue;
            };

            if (score > max) {
                max = score;
                bestMove = move;
            }
            if (score > alphaLocal) alphaLocal = score;
            if (alphaLocal >= beta) {
                if (!move.isCapture() and move.promotion_piecetype == null) {
                    self.addKiller(plyIndex(ply), move);
                    self.addHistory(board, side_to_move, move, depth);
                }
                break;
            }
        }

        var flag: u8 = 0;
        if (max <= alpha) {
            flag = 1;
        } else if (max >= beta) {
            flag = 2;
        }

        self.storeTT(zobrist, normalizeMateScore(max, ply), depth, flag, bestMove);

        return max;
    }

    pub fn searchRoot(
        self: *Search,
        chessBot: *ChessBot,
        allocator: std.mem.Allocator,
        board: *ZChess.Board,
        depth: i32,
        alpha: i32,
        beta: i32,
        hashMove: ?ZChess.Move,
        emit_info: bool,
    ) SearchResult {
        const moves = board.getPossibleMoves() catch |err| {
            chessBot.writeError("Failed to get possible moves ({})", .{err});
            return .{ .score = -Eval.MATE_VALUE, .best_move = null };
        };

        if (moves.len == 0) {
            return .{ .score = if (board.isInCheck() catch false) -Eval.MATE_VALUE else 0, .best_move = null };
        }

        var local_moves: [256]ZChess.Move = undefined;
        var heap_moves: ?[]ZChess.Move = null;
        defer if (heap_moves) |hm| allocator.free(hm);

        const ordered_moves = blk: {
            if (moves.len <= local_moves.len) {
                @memcpy(local_moves[0..moves.len], moves);
                break :blk local_moves[0..moves.len];
            }

            const hm = allocator.dupe(ZChess.Move, moves) catch {
                chessBot.writeError("Failed to copy moves for root search", .{});
                return .{ .score = -Eval.MATE_VALUE, .best_move = null };
            };
            heap_moves = hm;
            break :blk hm;
        };

        self.orderMoves(ordered_moves, board, hashMove, 0);

        var bestScore: i32 = -Eval.MATE_VALUE * 2;
        var bestMove: ?ZChess.Move = null;
        var alphaLocal = alpha;

        for (ordered_moves) |move| {
            const undo = board.makeMove(move) catch |err| {
                chessBot.writeError("Failed to make move ({})", .{err});
                continue;
            };

            const score = -self.searchNode(chessBot, allocator, board, depth - 1, -beta, -alphaLocal, 1);

            board.undoMove(undo) catch |err| {
                chessBot.writeError("Failed to undo move ({})", .{err});
                continue;
            };

            if (score > bestScore) {
                bestScore = score;
                bestMove = move;

                if (emit_info) {
                    chessBot.reportSearchInfo(board, depth, score, move) catch |err| {
                        chessBot.writeError("Failed to report search info ({})", .{err});
                    };
                }
            }

            if (score > alphaLocal) alphaLocal = score;
            if (alphaLocal >= beta) break;
        }

        return .{ .score = bestScore, .best_move = bestMove };
    }
};

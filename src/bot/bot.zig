const std = @import("std");
const RandGen = std.Random.DefaultPrng;

const ZChess = @import("zchess");

const Eval = @import("eval.zig");
const Search = @import("search.zig");
const UCI = @import("../uci.zig").UCI;

const NEG_INF = std.math.minInt(i32) + 1;
const POS_INF = std.math.maxInt(i32);

pub const ChessBot = struct {
    allocator: std.mem.Allocator,
    uci_interface: *UCI,
    search: Search.Search = undefined,
    nodes: u64 = 0,

    baseDepth: i32 = 0,

    pub fn new(allocator: std.mem.Allocator, interface: *UCI) ChessBot {
        var self = ChessBot{
            .allocator = allocator,
            .uci_interface = interface,
        };
        self.search = Search.Search.init(allocator, 1 << 20) catch |err| {
            self.writeError("Failed to initialize search: {!}", .{err});
            std.process.exit(1);
        };
        return self;
    }

    pub fn writeError(self: *ChessBot, comptime fmt: []const u8, args: anytype) void {
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
            const score = -self.search.negaMax(
                self,
                self.allocator,
                board,
                self.baseDepth,
                0,
                NEG_INF,
                POS_INF,
            );

            board.undoMove(undo) catch continue;
            if (score > bestScore) {
                bestScore = score;
                moveToPlay = move;
            }

            const moveStr = try moveToPlay.toString(self.allocator);
            defer self.allocator.free(moveStr);
            self.uci_interface.startInfo();
            self.uci_interface.writeInfo(.Depth, "{d}", .{self.baseDepth});
            self.uci_interface.writeInfo(.Score_cp, "{d}", .{score * @as(i32, if (board.turn == .White) 1 else -1)});
            self.uci_interface.writeInfo(.Pv, "{s}", .{moveStr});
            self.uci_interface.writeInfo(.Nodes, "{d}", .{self.nodes});
            self.uci_interface.endInfo();
        }

        return moveToPlay;
    }

    pub fn deinit(self: *ChessBot) void {
        self.search.deinit();
    }
};

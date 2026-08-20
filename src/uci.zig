// Implementation of a simple UCI (Universal Chess Interface) protocol handler in Zig.
const std = @import("std");
const ZChess = @import("zchess");
const Bot = @import("bot/bot.zig");

pub const UCIError = error{
    InvalidCommand,
    InvalidOption,
    InvalidPosition,
    InvalidMove,
    NotReady,
    UnknownError,
    UnknownCommand,
};

const startposition: []const u8 = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub const UCI = struct {
    allocator: std.mem.Allocator,
    board: ZChess.Board = undefined,
    stdout: std.Io.File.Writer,
    stdin: std.Io.File.Reader,

    moveGen: *ZChess.MoveGen,

    bot: Bot.ChessBot,

    running: bool = false,

    pub const InfoKind = enum {
        Depth,
        Score_cp,
        Score_mate,
        Nodes,
        Nps,
        Time,
        String,
        Pv,
    };

    pub fn new(allocator: std.mem.Allocator, stdout: std.Io.File.Writer, stdin: std.Io.File.Reader, moveGen: *ZChess.MoveGen) !UCI {
        const board = try ZChess.Board.emptyBoard(allocator, moveGen);
        return UCI{
            .allocator = allocator,
            .board = board,
            .stdout = stdout,
            .stdin = stdin,
            .bot = undefined,
            .moveGen = moveGen,
        };
    }

    pub fn setBot(self: *UCI, bot: Bot.ChessBot) void {
        self.bot = bot;
    }

    pub fn afterGoCommand(self: *UCI) !void {
        _ = self;
    }

    pub fn recieveFENLoadCommand(self: *UCI, cmd_str: []const u8, iterator: *std.mem.TokenIterator(u8, .any)) !void {
        const fenstart = iterator.index;
        for (0..6) |_| {
            if (iterator.next() == null) {
                return UCIError.InvalidPosition;
            }
        }
        const fenend = iterator.index;
        const fen = cmd_str[fenstart + 1 .. fenend]; // -1

        try self.board.loadFEN(fen);
    }

    pub fn startInfo(self: *UCI) void {
        _ = self.stdout.interface.write("info ") catch {};
    }
    pub fn writeInfo(self: *UCI, kind: ?InfoKind, comptime fmt: []const u8, args: anytype) void {
        if (kind) |k| {
            _ = self.stdout.interface.write(switch (k) {
                .Depth => "depth ",
                .Score_cp => "score cp ",
                .Score_mate => "score mate ",
                .Nodes => "nodes ",
                .Nps => "nps ",
                .Time => "time ",
                .Pv => "pv ",
                .String => "string ",
            }) catch return;
        }
        _ = self.stdout.interface.print(fmt, args) catch {};
        _ = self.stdout.interface.write(" ") catch {};
    }
    pub fn endInfo(self: *UCI) void {
        _ = self.stdout.interface.write("\n") catch {};
        _ = self.stdout.interface.flush() catch {};
    }

    pub fn recieveCommand(self: *UCI, cmd_str: []const u8) !void {
        if (std.mem.eql(u8, cmd_str, "uci")) {
            _ = try self.stdout.interface.write("uciok\n");
            try self.stdout.interface.flush();
            return;
        }
        if (std.mem.eql(u8, cmd_str, "isready")) {
            _ = try self.stdout.interface.write("readyok\n");
            try self.stdout.interface.flush();
            return;
        }
        if (std.mem.eql(u8, cmd_str, "ucinewgame")) {
            self.board.deinit();
            self.board = try ZChess.Board.emptyBoard(self.allocator, self.moveGen);
            return;
        }
        if (std.mem.eql(u8, cmd_str, "quit")) {
            self.running = false;
            self.bot.deinit();
            return;
        }
        if (std.mem.eql(u8, cmd_str, "legalmoves")) {
            const legalMoves = try self.board.getPossibleMoves();
            for (legalMoves) |move| {
                const moveStr = try move.toString(self.allocator);
                defer self.allocator.free(moveStr);
                _ = try self.stdout.interface.print("{s}\n", .{moveStr});
            }
            return;
        }
        if (std.mem.eql(u8, cmd_str, "debuginfo")) {
            self.board.printDebugInfo();
        }
        var tokenized = std.mem.tokenizeAny(u8, cmd_str, " ");
        const first = tokenized.next() orelse {
            return UCIError.InvalidCommand;
        };
        if (std.mem.eql(u8, first, "position")) {
            const loadtype = tokenized.next() orelse {
                return UCIError.InvalidCommand;
            };
            if (std.mem.eql(u8, loadtype, "fen")) {
                try self.recieveFENLoadCommand(cmd_str, &tokenized);
            } else if (std.mem.eql(u8, loadtype, "startpos")) {
                try self.board.loadFEN(startposition);
            }
            _ = tokenized.next() orelse {
                return;
            }; // Skip "moves"
            while (tokenized.next()) |next| {
                const classified = try self.board.classifyMove(try ZChess.Move.fromUCIStr(next));
                _ = try self.board.makeMove(classified);
            }
        }
        if (std.mem.eql(u8, first, "go")) {
            var requested_depth: ?i32 = null;
            var movetime_ms: i64 = 0;
            var wtime_ms: ?i64 = null;
            var btime_ms: ?i64 = null;
            var winc_ms: i64 = 0;
            var binc_ms: i64 = 0;
            var moves_to_go: ?i64 = null;

            while (tokenized.next()) |arg| {
                if (std.mem.eql(u8, arg, "depth")) {
                    if (tokenized.next()) |depth_str| {
                        requested_depth = std.fmt.parseInt(i32, depth_str, 10) catch requested_depth;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "movetime")) {
                    if (tokenized.next()) |time_str| {
                        movetime_ms = std.fmt.parseInt(i64, time_str, 10) catch movetime_ms;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "wtime")) {
                    if (tokenized.next()) |time_str| {
                        wtime_ms = std.fmt.parseInt(i64, time_str, 10) catch wtime_ms;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "btime")) {
                    if (tokenized.next()) |time_str| {
                        btime_ms = std.fmt.parseInt(i64, time_str, 10) catch btime_ms;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "winc")) {
                    if (tokenized.next()) |time_str| {
                        winc_ms = std.fmt.parseInt(i64, time_str, 10) catch winc_ms;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "binc")) {
                    if (tokenized.next()) |time_str| {
                        binc_ms = std.fmt.parseInt(i64, time_str, 10) catch binc_ms;
                    }
                    continue;
                }

                if (std.mem.eql(u8, arg, "movestogo")) {
                    if (tokenized.next()) |move_str| {
                        moves_to_go = std.fmt.parseInt(i64, move_str, 10) catch moves_to_go;
                    }
                    continue;
                }
            }

            var time_budget_ms = movetime_ms;
            if (time_budget_ms <= 0) {
                const remaining = if (self.board.turn == .White) wtime_ms else btime_ms;
                const increment = if (self.board.turn == .White) winc_ms else binc_ms;
                if (remaining) |rem| {
                    const moves_left = moves_to_go orelse 30;
                    var budget = @divTrunc(rem, @max(@as(i64, 1), moves_left)) + @divTrunc(increment * 7, 10);
                    budget -= 50;
                    if (budget < 10) budget = 10;
                    if (budget > @divTrunc(rem, 2)) budget = @divTrunc(rem, 2);
                    time_budget_ms = budget;
                }
            }

            const no_explicit_limits = requested_depth == null and movetime_ms <= 0 and wtime_ms == null and btime_ms == null;
            const move = if (no_explicit_limits)
                try self.bot.getMove(&self.board)
            else
                try self.bot.getMoveWithLimits(&self.board, time_budget_ms, requested_depth, true);

            const moveStr = try move.toString(self.allocator);
            defer self.allocator.free(moveStr);
            _ = try self.stdout.interface.print("bestmove {s}\n", .{moveStr});
            try self.stdout.interface.flush();

            const classified = try self.board.classifyMove(move);
            _ = try self.board.makeMove(classified);

            afterGoCommand(self) catch |err| {
                std.debug.print("Error after go command: {}\n", .{err});
            };
            return;
        }
    }

    pub fn run(self: *UCI) !void {
        self.running = true;
        while (self.running) {
            var line_alloc = std.Io.Writer.Allocating.init(self.allocator);
            defer line_alloc.deinit();

            const read_len = self.stdin.interface.streamDelimiter(&line_alloc.writer, '\n') catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };

            const line = try line_alloc.toOwnedSlice();
            defer self.allocator.free(line);
            self.stdin.interface.toss(1);

            if (read_len == 0) continue;
            const cmd_str = std.mem.trim(u8, line, "\r\n");

            try self.recieveCommand(cmd_str);
        }
    }

    pub fn deinit(self: *UCI) void {
        self.board.deinit();
    }
};

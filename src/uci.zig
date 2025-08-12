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
    stdout: std.fs.File.Writer,
    stdin: std.fs.File.Reader,

    moveGen: *ZChess.MoveGen,

    bot: Bot.ChessBot,

    running: bool = false,

    pub const InfoKind = enum {
        Depth,
        Score_cp,
        Score_mate,
        Nodes,
        Nps,
        String,
        Pv,
    };

    pub fn new(allocator: std.mem.Allocator, stdout: std.fs.File.Writer, stdin: std.fs.File.Reader, moveGen: *ZChess.MoveGen) !UCI {
        return UCI{
            .allocator = allocator,
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
        _ = self.stdout.write("info ") catch {};
    }
    pub fn writeInfo(self: *UCI, kind: ?InfoKind, comptime fmt: []const u8, args: anytype) void {
        if (kind) |k| {
            _ = self.stdout.write(switch (k) {
                .Depth => "depth ",
                .Score_cp => "score cp ",
                .Score_mate => "score mate ",
                .Nodes => "nodes ",
                .Nps => "nps ",
                .Pv => "pv ",
                .String => "string ",
            }) catch return;
        }
        _ = self.stdout.print(fmt, args) catch {};
        _ = self.stdout.write(" ") catch {};
    }
    pub fn endInfo(self: *UCI) void {
        _ = self.stdout.write("\n") catch {};
    }

    pub fn recieveCommand(self: *UCI, cmd_str: []const u8) !void {
        if (std.mem.eql(u8, cmd_str, "uci")) {
            _ = try self.stdout.write("uciok\n");
            return;
        }
        if (std.mem.eql(u8, cmd_str, "isready")) {
            _ = try self.stdout.write("readyok\n");
            return;
        }
        if (std.mem.eql(u8, cmd_str, "ucinewgame")) {
            self.board = try ZChess.Board.emptyBoard(self.allocator, self.moveGen);
            return;
        }
        if (std.mem.eql(u8, cmd_str, "quit")) {
            self.running = false;
            return;
        }
        if (std.mem.eql(u8, cmd_str, "legalmoves")) {
            const legalMoves = try self.board.getPossibleMoves(self.allocator);
            defer self.allocator.free(legalMoves);
            for (legalMoves) |move| {
                const moveStr = try move.toString(self.allocator);
                defer self.allocator.free(moveStr);
                _ = try self.stdout.print("{s}\n", .{moveStr});
            }
            return;
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
            const move = try self.bot.getMove(&self.board);

            const moveStr = try move.toString(self.allocator);
            defer self.allocator.free(moveStr);
            _ = try self.stdout.print("bestmove {s}\n", .{moveStr});

            const classified = try self.board.classifyMove(move);
            _ = try self.board.makeMove(classified);

            afterGoCommand(self) catch |err| {
                std.debug.print("Error after go command: {!}\n", .{err});
            };
            return;
        }
    }

    pub fn run(self: *UCI) !void {
        self.running = true;
        while (self.running) {
            const line = try self.stdin.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 1024) orelse {
                // EOF
                self.running = false;
                continue;
            };
            defer self.allocator.free(line);

            if (line.len == 0) {
                continue; // EOF or empty line
            }
            const cmd_str = std.mem.trim(u8, line, "\r\n");

            try self.recieveCommand(cmd_str);
        }
    }

    pub fn deinit(self: *UCI) void {
        self.board.deinit();
    }
};

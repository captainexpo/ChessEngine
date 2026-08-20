const std = @import("std");
const ZChess = @import("zchess");
const Bot = @import("bot/bot.zig");
const Color = @import("zchess").Color;
const UCI = @import("uci.zig").UCI;

pub const log_level: std.log.Level = .debug;

pub fn printMoves(allocator: std.mem.Allocator, moves: []ZChess.Move) !void {
    for (moves) |move| {
        const movestr = try move.toString(allocator);
        defer allocator.free(movestr);
        std.debug.print("{s}\n", .{movestr});
    }
}

pub fn stripWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;

    while (start < end and std.ascii.isWhitespace(s[start])) {
        start += 1;
    }

    while (end > start and std.ascii.isWhitespace(s[end - 1])) {
        end -= 1;
    }

    return s[start..end];
}

pub fn runUCI(allocator: std.mem.Allocator, io: std.Io) !void {
    var moveGen = ZChess.MoveGen.initMoveGeneration();

    const stdin_file = std.Io.File.stdin();
    var stdout_buffer: [4096]u8 = undefined;
    const stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);

    var stdin_buffer: [4096]u8 = undefined;
    const stdin = stdin_file.readerStreaming(io, &stdin_buffer);

    var uci = try UCI.new(allocator, stdout, stdin, &moveGen);
    defer uci.deinit();
    uci.setBot(Bot.ChessBot.new(allocator, &uci, io));
    uci.run() catch |err| {
        switch (err) {
            error.InvalidCommand => std.debug.print("Error: Invalid Command\n", .{}),
            error.InvalidOption => std.debug.print("Error: Invalid Option\n", .{}),
            error.InvalidPosition => std.debug.print("Error: Invalid Position\n", .{}),
            error.InvalidMove => std.debug.print("Error: Invalid Move\n", .{}),
            error.NotReady => std.debug.print("Error: Not Ready\n", .{}),
            error.UnknownError => std.debug.print("Error: Unknown Error\n", .{}),
            error.UnknownCommand => std.debug.print("Error: Unknown Command\n", .{}),
            else => std.debug.print("Error: {}\n", .{err}),
        }
    };
}

fn eqlMove(a: ZChess.Move, b: ZChess.Move) bool {
    const areEqual = a.from_square.toFlat() == b.from_square.toFlat() and a.to_square.toFlat() == b.to_square.toFlat() and a.promotion_piecetype == b.promotion_piecetype;
    return areEqual;
}

pub fn moveIsLegal(possibles: []const ZChess.Move, needle: ZChess.Move) bool {
    for (possibles) |thing| {
        if (eqlMove(thing, needle)) {
            return true;
        }
    }
    return false;
}

pub fn runCliGame(allocator: std.mem.Allocator, fenStr: []const u8, io: std.Io) !void {
    var moveGen = ZChess.MoveGen.initMoveGeneration();

    var board = try ZChess.Board.emptyBoard(allocator, &moveGen);
    defer board.deinit();

    const stdin_file = std.Io.File.stdin();
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin_file.readerStreaming(io, &stdin_buffer);

    try board.loadFEN(fenStr);
    var undo: ?ZChess.Board.MoveUndo = null;
    while (true) {
        const boardStr = try board.toString(allocator);
        defer allocator.free(boardStr);
        std.debug.print("{s}\n", .{boardStr});

        const possibleMoves = try board.getPossibleMoves();
        if (possibleMoves.len == 0) {
            std.debug.print("No legal moves available. Game over.\n", .{});
            break;
        }

        std.debug.print("{s}'s move: ", .{@tagName(board.turn)});

        var rms_alloc = std.Io.Writer.Allocating.init(allocator);
        defer rms_alloc.deinit();

        _ = try stdin_reader.interface.streamDelimiter(&rms_alloc.writer, '\n');
        stdin_reader.interface.toss(1);

        const rawMoveStr = try rms_alloc.toOwnedSlice();
        defer allocator.free(rawMoveStr);

        const moveStr = stripWhitespace(rawMoveStr);
        if (std.mem.eql(u8, rawMoveStr, "legalmoves")) {
            std.debug.print("Legal moves:\n", .{});
            try printMoves(allocator, possibleMoves);
            continue;
        } else if (std.mem.eql(u8, rawMoveStr, "exit")) {
            std.debug.print("Exiting game.\n", .{});
            break;
        } else if (std.mem.eql(u8, rawMoveStr, "boardinfo")) {
            board.printDebugInfo();
            continue;
        } else if (std.mem.eql(u8, rawMoveStr, "undo")) {
            if (undo) |u| {
                try board.undoMove(u);
                std.debug.print("Move undone.\n", .{});
            } else {
                std.debug.print("No move to undo.\n", .{});
            }
            continue;
        }

        const move = try ZChess.Move.fromUCIStr(moveStr);
        if (!moveIsLegal(possibleMoves, move)) {
            std.debug.print("Illegal move: {s}\n", .{moveStr});
            continue;
        }

        const classified = try board.classifyMove(move);
        undo = board.makeMove(classified) catch |err| {
            std.debug.print("Failed to make move: {}\n", .{err});
            continue;
        };
    }
}

const BenchPosition = struct {
    name: []const u8,
    fen: []const u8,
};

const bench_positions = [_]BenchPosition{
    .{ .name = "startpos", .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" },
    .{ .name = "opening pressure", .fen = "r1bqkbnr/pppp1ppp/2n5/1Bb1p3/3P4/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 4" },
    .{ .name = "middlegame", .fen = "r2q1rk1/ppp2ppp/2np1n2/1B2p3/3PP3/2N2N2/PPP2PPP/R1BQR1K1 w - - 2 9" },
    .{ .name = "tactical", .fen = "r4rk1/1pp1qppp/p1np1n2/4p3/2B1P3/2N2N2/PPPQ1PPP/R3K2R w KQ - 0 10" },
    .{ .name = "endgame", .fen = "8/8/8/2k5/8/5K2/6P1/8 w - - 0 1" },
    .{ .name = "queen attack", .fen = "rnb1kbnr/ppp1pppp/8/q2p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3" },
};

pub fn runBench(allocator: std.mem.Allocator, depth: i32, io: std.Io) !void {
    var moveGen = ZChess.MoveGen.initMoveGeneration();

    const stdin_file = std.Io.File.stdin();
    var stdout_buffer: [4096]u8 = undefined;
    const stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);

    var stdin_buffer: [4096]u8 = undefined;
    const stdin = stdin_file.readerStreaming(io, &stdin_buffer);

    var uci = try UCI.new(allocator, stdout, stdin, &moveGen);
    defer uci.deinit();
    uci.setBot(Bot.ChessBot.new(allocator, &uci, io));

    const bench_depth = if (depth < 1) 1 else depth;
    std.debug.print("Benchmark depth: {d}\n", .{bench_depth});
    std.debug.print("Positions: {d}\n", .{bench_positions.len});

    var total_nodes: u64 = 0;
    var total_ns: i128 = 0;

    var board = try ZChess.Board.emptyBoard(allocator, &moveGen);
    defer board.deinit();

    for (bench_positions, 0..) |position, index| {
        try board.loadFEN(position.fen);

        const started_ts = std.Io.Clock.now(.awake, io);
        const move = try uci.bot.getMoveWithLimits(&board, 0, bench_depth, false);
        const elapsed_duration = started_ts.durationTo(std.Io.Clock.now(.awake, io));

        const elapsed_ns: i128 = @intCast(elapsed_duration.toNanoseconds());

        const nodes = uci.bot.nodes;
        total_nodes += nodes;
        total_ns += @intCast(elapsed_ns);

        const move_str = try move.toString(allocator);
        defer allocator.free(move_str);

        const elapsed_ms = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) / 1_000_000.0;
        const nps = @as(f64, @floatFromInt(nodes)) * 1_000_000_000.0 / @as(f64, @floatFromInt(@max(elapsed_ns, 1)));
        std.debug.print("[{d}/{d}] {s}: {s} nodes={d} time={d:.2}ms nps={d:.0}\n", .{
            index + 1,
            bench_positions.len,
            position.name,
            move_str,
            nodes,
            elapsed_ms,
            nps,
        });
    }

    const total_ms = @as(f64, @floatFromInt(@max(total_ns, 1))) / 1_000_000.0;
    const total_nps = @as(f64, @floatFromInt(total_nodes)) * 1_000_000_000.0 / @as(f64, @floatFromInt(@max(total_ns, 1)));
    std.debug.print("\nTotal nodes: {d}\n", .{total_nodes});
    std.debug.print("Total time: {d:.2}ms\n", .{total_ms});
    std.debug.print("Total nps: {d:.0}\n", .{total_nps});
}

pub fn printHelp() void {
    std.debug.print("Usage: chess [run-uci|game|bench [depth]]\n", .{});
}

pub fn main(init: std.process.Init) !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    const init_arena = init.arena.allocator();
    const min = init.minimal;

    const io = init.io;

    const allocator = std.heap.page_allocator;

    const args = try min.args.toSlice(init_arena);

    if (args.len < 2) {
        try runUCI(allocator, io);
        return;
    }
    if (std.mem.eql(u8, args[1], "game")) {
        try runCliGame(allocator, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", io);
    } else if (std.mem.eql(u8, args[1], "bench")) {
        const depth = if (args.len >= 3) std.fmt.parseInt(i32, args[2], 10) catch 6 else 6;
        try runBench(allocator, depth, io);
    } else {
        printHelp();
    }
}

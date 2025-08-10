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

pub fn runUCI(allocator: std.mem.Allocator) !void {
    var moveGen = ZChess.MoveGen.initMoveGeneration();

    var uci = try UCI.new(allocator, std.io.getStdOut().writer(), std.io.getStdIn().reader(), &moveGen);
    defer uci.deinit();
    uci.setBot(Bot.ChessBot{
        .allocator = allocator,
    });
    try uci.run(); // catch |err| {
    //switch (err) {
    //    error.InvalidCommand => std.debug.print("Error: Invalid Command\n", .{}),
    //    error.InvalidOption => std.debug.print("Error: Invalid Option\n", .{}),
    //    error.InvalidPosition => std.debug.print("Error: Invalid Position\n", .{}),
    //    error.InvalidMove => std.debug.print("Error: Invalid Move\n", .{}),
    //    error.NotReady => std.debug.print("Error: Not Ready\n", .{}),
    //    error.UnknownError => std.debug.print("Error: Unknown Error\n", .{}),
    //    error.UnknownCommand => std.debug.print("Error: Unknown Command\n", .{}),
    //    else => std.debug.print("Error: {!}\n", .{err}),
    //}
    //};
}

fn eqlMove(a: ZChess.Move, b: ZChess.Move) bool {
    return a.from_square.toFlat() == b.from_square.toFlat() and a.to_square.toFlat() == b.to_square.toFlat() and a.promotion_piecetype == b.promotion_piecetype;
}

pub fn moveIsLegal(possibles: []const ZChess.Move, needle: ZChess.Move) bool {
    for (possibles) |thing| {
        if (eqlMove(thing, needle)) {
            return true;
        }
    }
    return false;
}

pub fn runCliGame(allocator: std.mem.Allocator, fenStr: []const u8) !void {
    var moveGen = ZChess.MoveGen.initMoveGeneration();

    var board = try ZChess.Board.emptyBoard(allocator, &moveGen);
    defer board.deinit();

    var stdin = std.io.getStdIn().reader();

    try board.loadFEN(fenStr);
    while (true) {
        const boardStr = try board.toString(allocator);
        defer allocator.free(boardStr);
        std.debug.print("{s}\n", .{boardStr});

        if (board.possibleMoves.len == 0) {
            std.debug.print("No legal moves available. Game over.\n", .{});
            break;
        }

        std.debug.print("{s}'s move: ", .{@tagName(board.turn)});
        const moveStr = try stdin.readUntilDelimiterAlloc(allocator, '\n', 16);
        defer allocator.free(moveStr);

        const move = try ZChess.Move.fromUCIStr(moveStr);
        while (!moveIsLegal(board.possibleMoves, move)) {
            std.debug.print("Illegal move: {s}\n", .{moveStr});
            continue;
        }

        try board.makeMove(move);
    }
}

pub fn printHelp() void {
    std.debug.print("Usage: chess [run-uci|game]\n", .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    if (std.mem.eql(u8, args[1], "run-uci")) {
        try runUCI(allocator);
    } else if (std.mem.eql(u8, args[1], "game")) {
        try runCliGame(allocator, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    } else {
        printHelp();
    }
}

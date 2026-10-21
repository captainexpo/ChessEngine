# ChessEngine

A UCI-compatible chess engine written in Zig, built on top of my chess library called [ZigChess](https://github.com/captainexpo/ZigChess).

## Features

### Search

The engine's search function is based around the Negamax algorithm. However, it contains additional features to speed up the search:

1. Alpha-beta pruning: Removes nodes that either aren't useful to the current player or are too powerful such that the opponent would never let them happen.
2. Transposition table: Caches previous evaluations for lookup later
3. Iterative deepening: Increases search depth iteratively
4. Null-move pruning: Search skips analysis of nodes where the opponent has made an obvious mistake as details of the refutaion don't really matter.
5. Move ordering: Searches potentially more powerful moves first (e.g. promotions, captures, checks) so that alpha-beta pruning can be more effective, faster.
6. Killer moves: Keeps track of moves that are exceptionally powerful and stores them for later just in case they may work again.
7. Asperation windows:

### Eval

The evaluation for the engine is relatively simple, consiting of only a few parts:

1. Piece scoring: Counts material value, square table evaluation, and piece visibility (how many squares it attacks).
2. Center control: How many pawns are near the center and how close they are to it.
3. Endgame evaluation: Currently, the only endgame specific eval is that closer kings = higher eval.

Even though these rules are relatively simple, when they are combined with the search they become much more powerful.

## Building

The engine is built for zig v0.16.0. Later versions of zig may fail to compile the engine due to language API changes.

To compile a debug build, run `zig build`. To compile a release build, run `zig build --release=fast`.


## Running

The engine speaks the [UCI protocol](https://en.wikipedia.org/wiki/Universal_Chess_Interface), so it can be used with any UCI-compatible chess GUI (e.g. Cute Chess, Arena, Banksia). I personally like [Cute Chess](https://www.cutechess.com/).

To start a game in the terminal, run `zig build run` or the raw executable.


# ZigChessBot

A UCI-compatible chess engine written in Zig, built on top of the [ZigChess](https://github.com/captainexpo/ZigChess) move-generation library.

## Building

```sh
zig build
```

## Running

The engine speaks the [UCI protocol](https://en.wikipedia.org/wiki/Universal_Chess_Interface), so it can be used with any UCI-compatible chess GUI (e.g. Cute Chess, Arena, Banksia).

```sh
zig build run
```

Or point your GUI at the built binary in `zig-out/bin/ZigChessBot`.

## Testing

```sh
zig build test
```

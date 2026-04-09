printf "ucinewgame\nposition startpos\ngo wtime 50000 btime 50000\nquit\n" | \
 sudo perf record -F 9999 --call-graph=fp zig-out/bin/ZigChessBot

sudo perf script | stackcollapse-perf.pl > out.folded
flamegraph.pl out.folded > flame.svg

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_local_zchess = true; // toggle to switch between local and fetched package

    var zchess_mod: *std.Build.Module = undefined;

    if (use_local_zchess) {
        zchess_mod = b.addModule("zchess", .{
            .root_source_file = b.path("../ZigChess/src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
    } else {
        // Use dependency fetched from remote
        zchess_mod = b.dependency("zig_chess", .{}).module("zchess");
    }

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ZigChessBot",
        .root_module = exe_mod,
    });

    exe.root_module.addImport("zchess", zchess_mod);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

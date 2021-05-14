const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("zig-engine", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Raylib 3.7
    exe.addLibPath("/opt/raylib/raylib-3.7.0/lib");
    exe.addSystemIncludeDir("/opt/raylib/raylib-3.7.0/include");
    exe.linkSystemLibrary("raylib");
   
    // Houdini Engine
    exe.addLibPath("/opt/hfs18.5/dsolib");
    exe.addSystemIncludeDir("/opt/hfs18.5/toolkit/include");
    exe.linkSystemLibrary("HAPIL");

    exe.linkLibC();


    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

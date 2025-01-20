const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("rc", .{
        .root_source_file = b.path("rc.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "run all unit tests");

    const rc_test = b.addTest(.{
        .name = "rc",
        .target = target,
        .optimize = .Debug,
        .root_source_file = b.path("rc.zig"),
    });
    test_step.dependOn(&b.addRunArtifact(rc_test).step);
}

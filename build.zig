const std = @import("std");
const builtin = @import("builtin");

const required_zig_version = std.SemanticVersion.parse("0.13.0") catch unreachable;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    if (comptime !versionEql(required_zig_version, builtin.zig_version)) {
        @compileError(std.fmt.comptimePrint("zig version required for zig-rc is {} but current is {}", .{ required_zig_version, builtin.zig_version }));
    }
    _ = b.addModule("rc", .{
        .root_source_file = b.path("rc.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "run all unit tests");

    const rc_test = b.addTest(.{
        .name = "rc_test",
        .target = target,
        .optimize = .Debug,
        .root_source_file = b.path("rc.zig"),
    });
    test_step.dependOn(&b.addRunArtifact(rc_test).step);
    b.installArtifact(rc_test);
}

fn versionEql(lhs: std.SemanticVersion, rhs: std.SemanticVersion) bool {
    return lhs.major == rhs.major and lhs.minor == rhs.minor and lhs.patch == rhs.patch;
}

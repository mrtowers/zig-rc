const std = @import("std");
const builtin = @import("builtin");

const required_zig_version = std.SemanticVersion.parse("0.15.0") catch unreachable;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (comptime !versionEql(required_zig_version, builtin.zig_version)) {
        @compileError(std.fmt.comptimePrint("zig version required for zig-rc is {any} but current is {any}", .{ required_zig_version, builtin.zig_version }));
    }

    const rc_mod = b.addModule("rc", .{
        .root_source_file = b.path("rc.zig"),
        .target = target,
        .optimize = optimize,
    });

    //steps
    const test_step = b.step("test", "run all unit tests");
    const coverage_step = b.step("coverage", "run the code coverage analysis");

    const rc_test = b.addTest(.{
        .name = "rc_test",
        .root_module = rc_mod,
    });
    test_step.dependOn(&b.addRunArtifact(rc_test).step);

    const kcov_bin = b.findProgram(&.{"kcov"}, &.{ "/bin", "/usr/bin" }) catch |e| {
        std.debug.panic("cannot find kcov binary: {}", .{e});
    };

    const coverage_run = std.Build.Step.Run.create(b, "coverage");
    coverage_run.addArg(kcov_bin);
    coverage_run.addArg("--include-path=.");

    const coverage_output_dir = coverage_run.addOutputDirectoryArg("cov");
    coverage_run.addArtifactArg(rc_test);

    const coverage_install_dir = b.addInstallDirectory(.{
        .source_dir = coverage_output_dir,
        .install_dir = .{ .custom = "coverage_out" },
        .install_subdir = "",
    });
    coverage_step.dependOn(&coverage_install_dir.step);
}

fn versionEql(lhs: std.SemanticVersion, rhs: std.SemanticVersion) bool {
    return lhs.major == rhs.major and lhs.minor == rhs.minor;
}

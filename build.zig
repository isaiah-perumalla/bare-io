const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("micronet", .{
        .source_file = .{ .path = "src/micronet.zig" },
    });

    const lib = b.addStaticLibrary(.{
        .name = "bare-io",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/micronet.zig" },
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const echo_example = b.addExecutable(.{
        .name = "echo",
        .root_source_file = .{ .path = "src/examples/echo.zig" },
        .target = target,
        .optimize = optimize,
    });
    echo_example.addModule("micronet", module);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const net_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/micronet.zig" },
        .target = target,
        .optimize = optimize,
    });

    const dns_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/dnsq.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_dns_tests = b.addRunArtifact(dns_tests);

    const run_net_tests = b.addRunArtifact(net_tests);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build test`
    // This will evaluate the `test` step rather than the default, which is "install".
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_net_tests.step);
    test_step.dependOn(&run_dns_tests.step);

    const build_examples_step = b.step("examples", "Builds all examples");
    build_examples_step.dependOn(&b.addInstallArtifact(echo_example, .{}).step);
}

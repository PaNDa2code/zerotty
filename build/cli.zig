const std = @import("std");
const Build = std.Build;

const profile_mod = @import("profile.zig");
const BuildProfile = profile_mod.BuildProfile;
const ResolvedConfig = profile_mod.ResolvedConfig;
const BuildProfileEnum = profile_mod.BuildProfileEnum;
const Window = profile_mod.Window;

pub const CliCommand = union(enum) {
    check,
    build: BuildProfile,
};

pub fn addOptions(b: *Build) CliCommand {
    const std_target_query = b.standardTargetOptionsQueryOnly(.{});
    const std_optimize = b.standardOptimizeOption(.{});

    _ = b.option([]const BuildProfileEnum, "build_profiles", "list of build profile");

    const use_llvm = b.option(bool, "use_llvm", "use llvm backend to build the project");
    const build_proflie = b.option(BuildProfileEnum, "profile", "predefined profiles just for easier build");

    const build_profile = if (build_proflie) |bp|
        bp.getProfile()
    else
        BuildProfile{
            .name = "native",
            .target = std_target_query,
            .optimize = std_optimize,
            .window = .glfw,
            .use_llvm = use_llvm,
        };

    return .{
        .build = build_profile,
    };
}

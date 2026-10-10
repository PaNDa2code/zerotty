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
    multi_build: []const BuildProfile,
};

pub fn addOptions(b: *Build) CliCommand {
    const std_target_query = b.standardTargetOptionsQueryOnly(.{});
    const std_optimize = b.standardOptimizeOption(.{});

    const build_profiles = b.option([]const BuildProfileEnum, "build_profiles", "list of build profiles to build in one run");

    const use_llvm = b.option(bool, "use_llvm", "use llvm backend to build the project");
    const build_profile_opt = b.option(BuildProfileEnum, "profile", "predefined profiles just for easier build");

    if (build_profiles) |profs| {
        if (profs.len > 0) {
            var list: std.ArrayList(BuildProfile) = .empty;
            for (profs) |bp| {
                var p = bp.getProfile();
                p.optimize = std_optimize;
                if (use_llvm) |llvm| p.use_llvm = llvm;
                list.append(b.allocator, p) catch @panic("OOM");
            }
            return .{
                .multi_build = list.toOwnedSlice(b.allocator) catch @panic("OOM"),
            };
        }
    }

    var build_profile = if (build_profile_opt) |bp|
        bp.getProfile()
    else
        BuildProfile{
            .name = "native",
            .target = std_target_query,
            .optimize = std_optimize,
            .window = .glfw,
            .use_llvm = use_llvm,
        };

    build_profile.optimize = std_optimize;
    if (use_llvm) |llvm| {
        build_profile.use_llvm = llvm;
    }

    return .{
        .build = build_profile,
    };
}

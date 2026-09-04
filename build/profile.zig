const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub const Window = enum {
    glfw,
    win32,
    xcb,
    android,
};

pub const BuildProfile = struct {
    name: []const u8,
    target: std.Target.Query,

    window: ?Window = null,
    optimize: ?std.builtin.OptimizeMode = null,
    use_llvm: ?bool = null,
};

pub fn resolveProfile(b: *Build, profile: BuildProfile) ResolvedConfig {
    validateProfile(profile) catch @panic("ProfileMismatch");

    const target = b.resolveTargetQuery(profile.target);

    const is_android = target.result.abi.isAndroid();

    const window: Window = profile.window orelse switch (target.result.os.tag) {
        .windows => .win32,
        .linux => if (is_android) .android else .xcb,
        else => .glfw,
    };

    const mode = profile.optimize orelse .Debug;
    const use_llvm = profile.use_llvm orelse (target.result.os.tag == .windows or is_android);

    return .{
        .name = profile.name,
        .target = target,
        .window = window,
        .optimize = mode,
        .use_llvm = use_llvm,
    };
}

pub const ResolvedConfig = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    window: Window,
    optimize: std.builtin.OptimizeMode,
    use_llvm: bool,
};

pub const PRESETS = [_]BuildProfile{
    .{ .name = "linux-glfw", .target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }, .window = .glfw },
    .{ .name = "linux-xcb", .target = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }, .window = .xcb },
    .{ .name = "windows-glfw", .target = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }, .window = .glfw },
    .{ .name = "windows", .target = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }, .window = .win32 },
    .{ .name = "android", .target = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android }, .window = .android },
};

pub const BuildProfileEnum = enum(usize) {
    linux_glfw = 0,
    linux_xcb = 1,
    windows_glfw = 2,
    windows = 3,
    android = 4,

    pub fn getProfile(e: BuildProfileEnum) BuildProfile {
        return PRESETS[@intFromEnum(e)];
    }

    pub fn getNative() BuildProfileEnum {
        return switch (builtin.os.tag) {
            .linux => .linux_glfw,
            .windows => .windows_glfw,
            else => unreachable,
        };
    }
};

pub fn fromName(name: []const u8) ?BuildProfile {
    for (PRESETS) |p| {
        if (std.mem.eql(u8, p.name, name)) return p;
    }
    return null;
}

fn validateProfile(profile: BuildProfile) !void {
    const window = profile.window orelse return;
    if (profile.target.os_tag) |os| {
        const is_android = if (profile.target.abi) |abi| abi.isAndroid() else false;
        switch (window) {
            .win32 => if (os != .windows) return error.ProfileMismatch,
            .xcb => if (os != .linux or is_android) return error.ProfileMismatch,
            .android => if (!is_android) return error.ProfileMismatch,
            .glfw => if (is_android) return error.ProfileMismatch,
        }
    }
}

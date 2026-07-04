const std = @import("std");

const app_mod = @import("app.zig");

var io = std.Io.Threaded.global_single_threaded.io();

pub const RenderBackend = enum {
    d3d11,
    opengl,
    vulkan,
    // webgpu,
};

pub const WindowSystem = enum {
    win32,
    xlib,
    xcb,
    glfw,
    // web,
};

const TargetConfigJson = struct {
    name: []const u8,
    target: []const u8,
    window_system: WindowSystem,
    render_backend: RenderBackend,
};

pub const AppConfig = struct {
    use_llvm: bool,
    comptime_check: bool,
    render_backend: RenderBackend,
    window_system: WindowSystem,
    disable_renderer_debug: bool,
};

pub fn jsonFileToStep(
    b: *std.Build,
    step: *std.Build.Step,
    json_path: []const u8,
    mode: std.builtin.OptimizeMode,
    use_llvm: bool,
) !void {
    const check_buffer = try b.allocator.alloc(u8, 2048);
    const check_configs_file = try std.Io.Dir.cwd().openFile(io, json_path, .{});
    const check_configs_data_len = try check_configs_file.readPositionalAll(io, check_buffer, 0);
    const json_parsed = try std.json.parseFromSlice([]TargetConfigJson, b.allocator, check_buffer[0..check_configs_data_len], .{});
    try addJsonTargetToStep(b, step, json_parsed.value, mode, use_llvm);
}

pub fn addJsonTargetToStep(
    b: *std.Build,
    step: *std.Build.Step,
    targets: []TargetConfigJson,
    mode: std.builtin.OptimizeMode,
    use_llvm: bool,
) !void {
    for (targets) |t_cfg| {
        const resolved_target = b.resolveTargetQuery(try .parse(.{ .arch_os_abi = t_cfg.target }));
        const dist_config = AppConfig{
            .use_llvm = use_llvm,
            .comptime_check = false,
            .render_backend = t_cfg.render_backend,
            .window_system = t_cfg.window_system,
            .disable_renderer_debug = false,
        };

        const dist_build = app_mod.setupApp(b, resolved_target, mode, dist_config) catch |err| {
            std.log.err("target({s}) => {}", .{ t_cfg.name, err });
            continue;
        };

        const dir_name = if (mode == .Debug)
            b.fmt("debug/{s}", .{t_cfg.name})
        else
            b.fmt("release/{s}", .{t_cfg.name});

        const install_dir = b.addInstallArtifact(dist_build.exe, .{
            .dest_dir = .{
                .override = .{ .custom = dir_name },
            },
        });

        step.dependOn(&install_dir.step);
    }
}

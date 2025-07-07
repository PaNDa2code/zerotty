const Builder = @This();

b: *Build,
target: ResolvedTarget,
optimize: OptimizeMode,
window_system: WindowSystem = undefined,
render_backend: RenderBackend = undefined,

builder_step: *Build.Step,

main_module: ?*Build.Module = null,
import_table: std.StringArrayHashMap(*Build.Module),

root_source_file: ?Build.LazyPath = null,

options_mod: ?OptionsModule = null,

exe: ?*Build.Step.Compile = null,

pub const RenderBackend = enum {
    D3D11,
    OpenGL,
    Vulkan,
};

pub const WindowSystem = enum {
    Win32,
    Xlib,
    Xcb,
};

pub const OptionsModule = struct {
    options: *Build.Step.Options,
    name: []const u8,
};

pub fn init(b: *Build, target: ?ResolvedTarget, optimize: ?OptimizeMode) Builder {
    return .{
        .b = b,
        .target = target orelse b.standardTargetOptions(.{}),
        .optimize = optimize orelse b.standardOptimizeOption(.{}),
        .builder_step = b.step("Builder", ""),
        .import_table = .init(b.allocator),
    };
}

pub fn setRenderBackend(self: *Builder, backend: RenderBackend) *Builder {
    self.render_backend = backend;
    return self;
}
pub fn setWindowSystem(self: *Builder, system: WindowSystem) *Builder {
    self.window_system = system;
    return self;
}

pub fn setRootFile(self: *Builder, path: Build.LazyPath) *Builder {
    self.root_source_file = path;
    return self;
}

pub fn getModule(self: *Builder) !*Build.Module {
    const mod = self.b.createModule(.{
        .root_source_file = self.root_source_file orelse @panic("root source file is not set"),
        .target = self.target,
        .optimize = self.optimize,
        .link_libc = self.needLibc(),
    });

    try self.addImports();

    var modules_iter = self.import_table.iterator();

    while (modules_iter.next()) |entry| {
        mod.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }

    self.linkSystemLibrarys(mod);

    return mod;
}

pub fn addOptionsModule(self: *Builder, name: []const u8, options: *Build.Step.Options) *Builder {
    self.options_mod = .{ .name = name, .options = options };
    return self;
}

pub fn addExcutable(self: *Builder, name: []const u8) *Builder {
    const exe = self.b.addExecutable(.{
        .name = name,
        .root_module = self.getModule() catch |e| std.debug.panic("Failed to create Module: {}", .{e}),
        .link_libc = self.needLibc(),
    });

    self.exe = exe;

    self.builder_step.dependOn(&exe.step);

    if (self.target.result.os.tag == .windows)
        exe.addWin32ResourceFile(.{
            .file = self.b.path("assets/zerotty.rc"),
        });

    return self;
}

pub fn addRunStep(self: *Builder) *Builder {
    if (self.exe) |e| {
        const run_cmd = self.b.addRunArtifact(e);

        run_cmd.step.dependOn(self.b.getInstallStep());

        if (self.b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = self.b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    } else @panic("no exe added");

    return self;
}

pub fn apply(self: *Builder) void {
    self.setInstallArtifact();
    self.b.default_step.dependOn(self.builder_step);
}

fn setInstallArtifact(self: *Builder) void {
    if (self.exe) |exe| {
        self.b.installArtifact(exe);
    }
}

fn addImports(self: *Builder) !void {
    switch (self.target.result.os.tag) {
        .windows => {
            const win32_mod = self.b.dependency("zigwin32", .{}).module("win32");
            try self.import_table.put("win32", win32_mod);
        },
        .linux => {
            const zig_openpty = self.b.dependency("zig_openpty", .{});
            const openpty_mod = zig_openpty.module("openpty");
            try self.import_table.put("openpty", openpty_mod);
        },
        .macos => {},
        else => {},
    }

    switch (self.render_backend) {
        .D3D11 => {},
        .OpenGL => {
            try self.import_table.put("gl", self.getOpenGLBindings());
        },
        .Vulkan => {
            const vulkan = self.b.dependency("vulkan", .{
                .registry = self.b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
            });

            const vulkan_mod = vulkan.module("vulkan-zig");
            try self.import_table.put("vulkan", vulkan_mod);
        },
    }

    if (self.options_mod) |mod| {
        try self.import_table.put(mod.name, mod.options.createModule());
    }

    const vtparse = self.b.dependency("vtparse", .{
        .target = self.target,
        .optimize = self.optimize,
    });
    const vtparse_mod = vtparse.module("vtparse");

    const freetype = self.b.dependency("zig_freetype2", .{
        .target = self.target,
        .optimize = self.optimize,
    });
    const freetype_mod = freetype.module("zig_freetype2");

    try self.import_table.put("vtparse", vtparse_mod);
    try self.import_table.put("freetype", freetype_mod);

    const assets_mod = self.b.addModule("assets", .{
        .root_source_file = self.b.path("assets/assets.zig"),
    });

    try self.import_table.put("assets", assets_mod);
}

fn linkSystemLibrarys(self: *Builder, module: *Build.Module) void {
    switch (self.window_system) {
        .Win32 => {},
        .Xlib => {
            module.linkSystemLibrary("X11", .{});
            if (self.render_backend == .OpenGL) module.linkSystemLibrary("GL", .{});
        },
        .Xcb => {
            module.linkSystemLibrary("xcb", .{});
        },
    }
}

fn shouldUseGLES(self: *Builder) bool {
    return switch (self.target.result.os.tag) {
        .emscripten, .wasi, .ios => true,
        .linux, .windows => switch (self.target.result.cpu.arch) {
            .arm, .armeb, .aarch64 => true,
            else => false,
        },
        else => false,
    };
}

fn getOpenGLBindings(self: *Builder) *Build.Module {
    const extensions = &.{ .KHR_debug, .ARB_shader_storage_buffer_object };

    const gl_bindings = @import("zigglgen").generateBindingsModule(
        self.b,
        if (self.shouldUseGLES()) .{
            .api = .gles,
            .version = .@"3.2",
            .extensions = extensions,
        } else .{
            .api = .gl,
            .version = .@"4.0",
            .profile = .core,
            .extensions = extensions,
        },
    );

    return gl_bindings;
}

// TODO:
fn needLibc(self: *Builder) bool {
    _ = self;
    return true;
}

const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

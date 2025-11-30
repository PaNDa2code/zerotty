const Builder = @This();

b: *Build,
target: ResolvedTarget,
optimize: OptimizeMode,
window_system: WindowSystem = undefined,
render_backend: RenderBackend = undefined,

builder_step: *Build.Step,

main_module: ?*Build.Module = null,
import_table: std.StringArrayHashMap(*Build.Module),
link_table: std.ArrayList(*Build.Step.Compile),
linkage: std.builtin.LinkMode,

root_source_file: ?Build.LazyPath = null,

options_mod: ?OptionsModule = null,

exe: ?*Build.Step.Compile = null,
lib: ?*Build.Step.Compile = null,

pub const RenderBackend = enum {
    D3D11,
    OpenGL,
    Vulkan,
};

pub const WindowSystem = enum {
    Win32,
    Xlib,
    Xcb,
    GLFW,
};

pub const OptionsModule = struct {
    options: *Build.Step.Options,
    name: []const u8,
};

var counter: std.atomic.Value(u32) = .init(0);

pub fn init(b: *Build, target: ?ResolvedTarget, optimize: ?OptimizeMode) Builder {
    const target_ = target orelse b.standardTargetOptions(.{});
    const is_native = target_.query.isNativeOs();
    const is_gnu = target_.result.isGnuLibC();
    return .{
        .b = b,
        .target = target_,
        .optimize = optimize orelse b.standardOptimizeOption(.{}),
        .builder_step = b.step(b.fmt("Builder{}", .{counter.fetchAdd(1, .acq_rel)}), ""),
        .import_table = .init(b.allocator),
        .link_table = .empty,
        .linkage = if (is_gnu and is_native) .dynamic else .static,
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

pub fn addCheckStep(self: *Builder, add: bool) *Builder {
    if (add)
        @import("check.zig").addCheckStep(self.b) catch unreachable;
    return self;
}

pub fn getModule(self: *Builder) *Build.Module {
    if (self.main_module) |mod| {
        return mod;
    }

    const mod = self.b.createModule(.{
        .root_source_file = self.root_source_file orelse @panic("root source file is not set"),
        .target = self.target,
        .optimize = self.optimize,
        .link_libc = self.needLibc(),
    });

    self.addImports();
    self.linkLibrarys(mod);

    var modules_iter = self.import_table.iterator();

    while (modules_iter.next()) |entry| {
        mod.addImport(entry.key_ptr.*, entry.value_ptr.*);
    }

    return mod;
}

pub fn addOptionsModule(self: *Builder, name: []const u8, options: *Build.Step.Options) *Builder {
    self.options_mod = .{ .name = name, .options = options };
    return self;
}

pub fn addExcutable(self: *Builder, name: []const u8) *Builder {
    const exe = self.b.addExecutable(.{
        .name = name,
        .root_module = self.getModule(),
    });

    // debug builds needs a console
    if (self.window_system == .Win32 and self.optimize != .Debug) {
        exe.subsystem = .Windows;
        exe.mingw_unicode_entry_point = true;
        exe.bundle_compiler_rt = true;
    }

    self.builder_step.dependOn(&exe.step);

    exe.addWin32ResourceFile(.{
        .file = self.b.path("assets/zerotty.rc"),
    });

    self.exe = exe;

    return self;
}

pub fn addStaticLibrary(self: *Builder, name: []const u8) *Builder {
    const lib = self.b.addLibrary(.{
        .name = name,
        .root_module = self.getModule(),
        .linkage = .static,
    });

    self.lib = lib;
    self.builder_step.dependOn(&lib.step);

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

fn addImports(self: *Builder) void {
    switch (self.target.result.os.tag) {
        .windows => {
            if (self.b.lazyDependency("zigwin32", .{})) |dep| {
                const win32_mod = dep.module("win32");
                self.import_table.put("win32", win32_mod) catch unreachable;
            }
        },
        .linux => {
            if (self.b.lazyDependency("zig_openpty", .{})) |dep| {
                const openpty_mod = dep.module("openpty");
                self.import_table.put("openpty", openpty_mod) catch unreachable;
            }
        },
        .macos => {},
        else => {},
    }

    switch (self.render_backend) {
        .D3D11 => {},
        .OpenGL => {
            self.import_table.put("gl", self.getOpenGLBindings()) catch unreachable;
        },
        .Vulkan => {
            var vulkan: ?*Build.Dependency = null;
            const vulkan_headers = self.b.lazyDependency("vulkan_headers", .{});

            if (vulkan_headers) |vk_headers| {
                vulkan = self.b.lazyDependency("vulkan", .{ .registry = vk_headers.path("registry/vk.xml") });
            } else _ = self.b.lazyDependency("vulkan", .{});

            if (vulkan) |dep| {
                const vulkan_mod = dep.module("vulkan-zig");
                self.import_table.put("vulkan", vulkan_mod) catch unreachable;
            }
        },
    }

    if (self.options_mod) |mod| {
        self.import_table.put(mod.name, mod.options.createModule()) catch unreachable;
    }

    const vtparse = self.b.dependency("vtparse", .{
        .target = self.target,
        .optimize = self.optimize,
    });
    const vtparse_mod = vtparse.module("vtparse");

    const freetype = self.b.dependency("freetype", .{
        .target = self.target,
        .optimize = self.optimize,
    });

    const harfbuzz = self.b.dependency("harfbuzz", .{
        .target = self.target,
        .optimize = self.optimize,
        .enable_freetype = true,
    });

    const harfbuzz_mod = harfbuzz.module("harfbuzz");

    const freetype_mod = freetype.module("freetype");

    self.import_table.put("vtparse", vtparse_mod) catch unreachable;
    self.import_table.put("freetype", freetype_mod) catch unreachable;
    self.import_table.put("harfbuzz", harfbuzz_mod) catch unreachable;

    const compiled_shaders = @import("shaders.zig").compiledShadersPathes(
        self.b,
        self.b.path("src/renderer/shaders"),
        &.{ "cell.frag", "cell.vert" },
        self.render_backend,
    ) catch unreachable;

    const assets_mod = self.b.addModule("assets", .{
        .root_source_file = self.b.path("assets/assets.zig"),
    });

    @import("shaders.zig").addCompiledShadersToModule(compiled_shaders, assets_mod);

    self.import_table.put("assets", assets_mod) catch unreachable;

    const zigimg = self.b.dependency("zigimg", .{
        .target = self.target,
        .optimize = self.optimize,
    });
    const zigimg_mod = zigimg.module("zigimg");
    self.import_table.put("zigimg", zigimg_mod) catch unreachable;
}

fn linkLibrarys(self: *Builder, module: *Build.Module) void {
    switch (self.window_system) {
        .Win32 => {},
        .Xlib => {
            module.linkSystemLibrary("X11", .{ .needed = true });
            if (self.render_backend == .OpenGL) module.linkSystemLibrary("GL", .{});
        },
        .Xcb => {
            if (self.target.query.isNativeOs()) {
                module.linkSystemLibrary("xcb", .{});
                module.linkSystemLibrary("xkbcommon", .{});
            } else {
                if (self.b.lazyDependency("xcb", .{
                    .target = self.target,
                    .optimize = self.optimize,
                    .linkage = self.linkage,
                })) |dep| {
                    const libxcb = dep.artifact("xcb");
                    module.linkLibrary(libxcb);
                }
                if (self.b.lazyDependency("xkbcommon", .{
                    .target = self.target,
                    .optimize = self.optimize,
                    .@"xkb-config-root" = "/usr/share/X11/xkb",
                })) |dep| {
                    const libxkbcommon = dep.artifact("xkbcommon");
                    module.linkLibrary(libxkbcommon);
                }
            }
        },
        .GLFW => {
            module.linkSystemLibrary("glfw", .{});
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
    const extensions: []const []const u8 = &.{
        "KHR_debug",
        "ARB_shader_storage_buffer_object",
        "ARB_gl_spirv",
    };

    const target = if (self.shouldUseGLES()) "gles-3.2" else "gl-4.1-core";

    const gl = self.b.createModule(.{});

    if (self.b.lazyDependency("zigglgen", .{})) |dep| {
        const zigglgen_exe = dep.artifact("zigglgen");
        const zigglgen_run = self.b.addRunArtifact(zigglgen_exe);
        zigglgen_run.addArg(target);
        for (extensions) |extension| {
            zigglgen_run.addArg(extension);
        }

        const output = zigglgen_run.captureStdOut();
        zigglgen_run.captured_stdout.?.basename = "gl.zig";
        gl.root_source_file = output;
    }

    return gl;
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

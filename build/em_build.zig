// https://github.com/floooh/sokol-zig/blob/master/build.zig

const std = @import("std");
const builtin = @import("builtin");

pub fn emsdkSetup(b: *std.Build, emsdk: *std.Build.Dependency) ?*std.Build.Step.Run {
    const dot_emsc_path = emSdkLazyPath(b, emsdk, &.{".emscripten"}).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}

fn emSdkLazyPath(b: *std.Build, emsdk: *std.Build.Dependency, sub_paths: []const []const u8) std.Build.LazyPath {
    return emsdk.path(b.pathJoin(sub_paths));
}

fn createEmsdkStep(b: *std.Build, emsdk: *std.Build.Dependency) *std.Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emSdkLazyPath(b, emsdk, &.{"emsdk.bat"}).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emSdkLazyPath(b, emsdk, &.{"emsdk"}).getPath(b));
        return step;
    }
}

pub fn emTool(b: *std.Build, emsdk: *std.Build.Dependency, tool: []const u8) std.Build.LazyPath {
    return emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", tool });
}

pub const EmLinkOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    lib_main: *std.Build.Step.Compile,
    emsdk: *std.Build.Dependency,
    exports: []const []const u8 = &.{},
    export_all: bool = false,
    release_use_closure: bool = false,
    release_use_lto: bool = false,
    standalone_wasm: bool = false,
    no_entry: bool = false,
    use_webgpu: bool = false,
    use_webgl2: bool = false,
    full_es3: bool = false,
    use_emmalloc: bool = false,
    use_offset_converter: bool = false,
    use_filesystem: bool = false,
    shell_file_path: ?std.Build.LazyPath = null,
    extra_args: []const []const u8 = &.{},
};
pub fn emLinkStep(b: *std.Build, options: EmLinkOptions) !*std.Build.Step.InstallDir {
    const emcc_path = emTool(b, options.emsdk, "emcc").getPath(b);
    const emcc = b.addSystemCommand(&.{emcc_path});
    emcc.setName("emcc linking"); // hide emcc path
    if (b.verbose_link) {
        emcc.addArg("-v");
    }
    if (options.target.result.cpu.arch == .wasm64) {
        emcc.addArg("-mwasm64");
    }
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArg("-flto");
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (options.standalone_wasm) {
        emcc.addArgs(&.{ "-s", "STANDALONE_WASM" });
    }
    if (options.export_all) {
        emcc.addArg("--export-all");
    }
    if (options.no_entry) {
        emcc.addArg("--no-entry");
    }
    if (options.use_webgpu) {
        emcc.addArg("--use-port=emdawnwebgpu");
    }
    if (options.use_webgl2) {
        emcc.addArg("-sUSE_WEBGL2=1");
    }
    if (options.full_es3) {
        emcc.addArg("-sFULL_ES3=1");
    }
    if (!options.use_filesystem) {
        emcc.addArg("-sNO_FILESYSTEM=1");
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.use_offset_converter) {
        emcc.addArg("-sUSE_OFFSET_CONVERTER=1");
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addPrefixedFileArg("--shell-file=", shell_file_path);
    }
    for (options.extra_args) |arg| {
        emcc.addArg(arg);
    }

    var export_list = std.ArrayList([]const u8).init(b.allocator);
    defer export_list.deinit();

    for (options.exports) |exp| {
        try export_list.append(b.fmt("'_{s}'", .{exp}));
    }

    const joined = std.mem.join(b.allocator, ",", export_list.items) catch unreachable;
    emcc.addArg(b.fmt("-sEXPORTED_FUNCTIONS=[{s}]", .{joined}));

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    for (options.lib_main.getCompileDependencies(false)) |item| {
        if (item.kind == .lib) {
            emcc.addArtifactArg(item);
        }
    }
    const out_file = emcc.addPrefixedOutputFileArg("-o", b.fmt("{s}.html", .{options.lib_main.name}));

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);
    return install;
}

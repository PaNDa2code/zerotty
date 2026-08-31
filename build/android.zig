const std = @import("std");
const Build = std.Build;
const builtin = @import("builtin");

pub const Ndk = struct {
    cli_path: Build.LazyPath,

    pub fn init(path: Build.LazyPath) Ndk {
        return .{ .cli_path = path };
    }

    /// Generates a libc.txt for Zig's `--libc` option, pointing at the NDK's
    /// sysroot as shipped by the modern NDK layout:
    ///
    ///   <ndk>/toolchains/llvm/prebuilt/<host>/sysroot/usr/include
    ///   <ndk>/toolchains/llvm/prebuilt/<host>/sysroot/usr/include/<triple>
    ///   <ndk>/toolchains/llvm/prebuilt/<host>/sysroot/usr/lib/<triple>/<api>
    ///
    /// Notes on the NDK layout (r23+):
    ///   - The `sysroot` lives under the toolchain prebuilt dir, not at the
    ///     NDK root, so the old top level `include`/`sysroot` paths are stale.
    ///   - CRT objects (`crtbegin_*.o`, `crtend_*.o`) and the `.so` system
    ///     libs are split per API level under `sysroot/usr/lib/<triple>/<api>`,
    ///     while the static `.a` libs sit one level up. Because of that split,
    ///     linking must be done dynamically for everything to resolve from a
    ///     single `crt_dir` (use `.linkage = .dynamic` / `-dynamic`).
    pub fn createLibcFile(
        ndk: Ndk,
        b: *Build,
        target: Build.ResolvedTarget,
        api_level: u32,
    ) !Build.LazyPath {
        const path = try ndk.cli_path.getPath4(b, null);

        const ndk_root = try path.root_dir.join(
            b.allocator,
            &.{path.sub_path},
        );

        const sysroot = b.fmt("{s}/toolchains/llvm/prebuilt/{s}/sysroot", .{
            ndk_root,
            hostPrebuiltDir(),
        });

        const triple = ndkTriple(target.result.cpu.arch);

        const write = b.addWriteFiles();

        const content = b.fmt(
            \\include_dir={0s}/usr/include
            \\sys_include_dir={0s}/usr/include/{1s}
            \\crt_dir={0s}/usr/lib/{1s}/{2d}
            \\msvc_lib_dir=
            \\kernel32_lib_dir=
            \\gcc_dir=
        , .{ sysroot, triple, api_level });

        return write.add("libc.txt", content);
    }

    /// adds the glue layer C code and let you import the translated
    /// headers using `@import(module_name)`
    pub fn importAndroidNativeGlue(
        ndk: Ndk,
        b: *Build,
        mod: *Build.Module,
        module_name: []const u8,
        sysroot_include: Build.LazyPath,
        sysroot_arch_include: Build.LazyPath,
    ) void {
        const glue_dir = ndk.cli_path.path(b, "sources/android/native_app_glue");

        mod.addCSourceFile(.{
            .file = glue_dir.path(b, "android_native_app_glue.c"),
        });

        const native_app_glue_translate = b.addTranslateC(.{
            .root_source_file = glue_dir.path(b, "android_native_app_glue.h"),
            .target = mod.resolved_target.?,
            .optimize = mod.optimize.?,
        });
        // Add the NDK sysroot include dirs so translate-c can find system headers
        // like <poll.h>, <android/log.h>, <asm/poll.h>, etc.
        native_app_glue_translate.addSystemIncludePath(sysroot_include);
        native_app_glue_translate.addSystemIncludePath(sysroot_arch_include);
        // Suppress NDK nullability annotations that zig translate-c can't handle
        // (e.g. `_Nullable` applied to array types in sys/time.h).
        native_app_glue_translate.defineCMacro("_Nullable", "");
        native_app_glue_translate.defineCMacro("_Nonnull", "");
        native_app_glue_translate.defineCMacro("_Null_unspecified", "");

        const native_app_glue_mod = native_app_glue_translate.createModule();
        mod.addImport(module_name, native_app_glue_mod);
    }
};

const Sdk = struct {
    path: Build.LazyPath,
    root: ?Build.LazyPath,

    pub fn init(path: Build.LazyPath) Sdk {
        return .{ .path = path, .root = null };
    }

    pub fn sdkmanager(sdk: Sdk, b: *Build) *Build.Step.Run {
        const run = std.Build.Step.Run.create(b, "run sdkmanager");

        run.addFileArg(sdk.path.path(b, "bin/sdkmanager"));

        run.setStdIn(.{ .bytes = "y\n" ** 100 });

        return run;
    }

    pub fn sdkmanagerDownload(
        sdk: *Sdk,
        b: *Build,
        args: []const []const u8,
    ) void {
        const sdkmanager_run = sdk.sdkmanager(b);

        const sdk_root = sdkmanager_run.addPrefixedOutputDirectoryArg("--sdk_root=", "android-sdk");
        sdkmanager_run.addArgs(args);

        sdk.root = sdk_root;
    }

    pub fn aapt2(sdk: Sdk, b: *Build, build_tools_version: []const u8) *Build.Step.Run {
        const run = std.Build.Step.Run.create(b, "run aapt2");

        if (sdk.root) |skd_root| {
            const sub_path = b.pathJoin(&.{ "build-tools", build_tools_version, "aapt2" });
            run.addFileArg(skd_root.path(b, sub_path));
        }

        return run;
    }

    pub fn androidJar(sdk: Sdk, b: *Build, version: []const u8) Build.LazyPath {
        if (sdk.root) |sdk_root|
            return sdk_root.path(b, b.fmt("platforms/android-{s}/android.jar", .{version}));

        @panic("sdk_root is null, use sdkmanager to install the sdk");
    }

    pub fn zipalign(sdk: Sdk, b: *Build) *Build.Step.Run {
        const run = std.Build.Step.Run.create(b, "run zipalign");
        run.addFileArg(sdk.root.?.path(b, "build-tools/34.0.0/zipalign"));
        return run;
    }

    pub fn apksigner(sdk: Sdk, b: *Build) *Build.Step.Run {
        const run = std.Build.Step.Run.create(b, "run apksigner");
        // apksigner is a shell script wrapper, but it works exactly the same
        run.addFileArg(sdk.root.?.path(b, "build-tools/34.0.0/apksigner"));
        return run;
    }
};

fn hostPrebuiltDir() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => switch (builtin.os.tag) {
            .linux => "linux-x86_64",
            .windows => "windows-x86_64",
            .macos => "darwin-x86_64",
            else => @panic("unsupported NDK host"),
        },
        .aarch64 => switch (builtin.os.tag) {
            .linux => "linux-aarch64",
            .macos => "darwin-arm64",
            else => @panic("unsupported NDK host"),
        },
        else => @panic("unsupported NDK host architecture"),
    };
}

fn ndkTriple(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .aarch64 => "aarch64-linux-android",
        .arm => "arm-linux-androideabi",
        .x86_64 => "x86_64-linux-android",
        .x86 => "i686-linux-android",
        .riscv64 => "riscv64-linux-android",
        else => @panic("unsupported Android NDK architecture"),
    };
}

fn androidAbi(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .aarch64 => "arm64-v8a",
        .arm => "armeabi-v7a",
        .x86_64 => "x86_64",
        .x86 => "x86",
        .riscv64 => "riscv64",
        else => @panic("unsupported Android ABI"),
    };
}

const android_manifest_fmt =
    \\<?xml version="1.0" encoding="utf-8"?>
    \\<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    \\   package="com.example.zerotty"
    \\   android:versionCode="{s}"
    \\   android:versionName="{s}">
    \\
    \\   <uses-sdk android:minSdkVersion="{s}" android:targetSdkVersion="{s}" />
    \\
    \\   <application 
    \\       android:hasCode="false" 
    \\       android:label="ZeroTTY">
    \\       
    \\       <activity android:name="android.app.NativeActivity"
    \\                 android:exported="true">
    \\           <meta-data android:name="android.app.lib_name" 
    \\                      android:value="zerotty" />
    \\           <intent-filter>
    \\               <action android:name="android.intent.action.MAIN" />
    \\               <category android:name="android.intent.category.LAUNCHER" />
    \\           </intent-filter>
    \\       </activity>
    \\   </application>
    \\</manifest>
;

fn getAndroidManifest(
    b: *Build,
    version_code: []const u8,
    version_name: []const u8,
    min_sdk_version: []const u8,
    max_sdk_version: []const u8,
) Build.LazyPath {
    const write_file = b.addWriteFile(
        "AndroidManifest.xml",
        b.fmt(android_manifest_fmt, .{
            version_code,
            version_name,
            min_sdk_version,
            max_sdk_version,
        }),
    );

    return write_file.getDirectory().path(b, "AndroidManifest.xml");
}

pub fn buildAndroidApk(b: *Build, archs: []const u8) ?Build.LazyPath {
    const ndk_dep = b.lazyDependency("ndk_linux", .{}) orelse return null;
    const android_cli_dep = b.lazyDependency("android_cli_tools_linux", .{}) orelse return null;

    const ndk = Ndk.init(ndk_dep.path("."));

    var sdk = Sdk.init(android_cli_dep.path("."));
    sdk.sdkmanagerDownload(b, &.{ "platforms;android-34", "build-tools;34.0.0" });

    var arch_iter = std.mem.splitScalar(u8, archs, ',');
    var target_list = std.ArrayListUnmanaged(Build.ResolvedTarget).empty;

    while (arch_iter.next()) |arch_str| {
        const arch = std.meta.stringToEnum(std.Target.Cpu.Arch, arch_str) orelse @panic("undefined arch");

        const query_str = switch (arch) {
            .arm => "arm-linux-androideabi",
            .aarch64 => "aarch64-linux-android",
            .x86 => "x86-linux-android",
            .x86_64 => "x86_64-linux-android",
            .riscv64 => "riscv64-linux-android",
            else => @panic("unsupported Android architecture query"),
        };

        const query = std.Target.Query.parse(.{ .arch_os_abi = query_str }) catch @panic("invalid arch query");
        target_list.append(b.allocator, b.resolveTargetQuery(query)) catch @panic("OOM");
    }

    const api_level: u32 = 30;

    const so_dir = b.addWriteFiles();

    for (target_list.items) |target| {
        const name = "zerotty";

        const libc_file = ndk.createLibcFile(b, target, api_level) catch @panic("failed to create libc file");

        const sysroot_include = ndk.cli_path.path(b, b.fmt(
            "toolchains/llvm/prebuilt/{s}/sysroot/usr/include",
            .{hostPrebuiltDir()},
        ));

        const triple = ndkTriple(target.result.cpu.arch);
        const sysroot_arch_include = ndk.cli_path.path(b, b.fmt(
            "toolchains/llvm/prebuilt/{s}/sysroot/usr/include/{s}",
            .{ hostPrebuiltDir(), triple },
        ));

        const mod = b.createModule(.{
            .target = target,
            .optimize = .ReleaseSmall,
            .root_source_file = b.path("src/android_main.zig"),
        });

        ndk.importAndroidNativeGlue(b, mod, "android_native_glue", sysroot_include, sysroot_arch_include);

        const so = b.addLibrary(.{
            .name = name,
            .root_module = mod,
        });

        so.setLibCFile(libc_file);

        const abi_name = androidAbi(target.result.cpu.arch);
        _ = so_dir.addCopyFile(so.getEmittedBin(), b.fmt("lib/{s}/lib{s}.so", .{ abi_name, name }));
    }

    const manifest_file = getAndroidManifest(b, "1", "1.0", "21", "34");

    const aapt2_run = sdk.aapt2(b, "34.0.0");

    aapt2_run.addArgs(&.{ "link", "-o" });

    const unaligned_apk = aapt2_run.addOutputFileArg("zerotty-unaligned.apk");

    aapt2_run.addArg("--manifest");
    aapt2_run.addFileArg(manifest_file);
    aapt2_run.addArg("-I");
    aapt2_run.addFileArg(sdk.androidJar(b, "34"));

    const zip_run = b.addSystemCommand(&.{"zip"});

    zip_run.setCwd(so_dir.getDirectory());
    zip_run.addArgs(&.{ "-q", "-r" });
    zip_run.addFileArg(unaligned_apk);
    zip_run.addArg("lib");
    zip_run.addArg("--out");

    const combined_apk = zip_run.addOutputFileArg("zerotty-combined.apk");

    const zipalign_run = sdk.zipalign(b);

    zipalign_run.addArgs(&.{ "-f", "-p", "4" });
    zipalign_run.addFileArg(combined_apk);

    const aligned_apk = zipalign_run.addOutputFileArg("zerotty-aligned.apk");

    const apksigner_run = sdk.apksigner(b);
    apksigner_run.addArgs(&.{ "sign", "--ks" });
    apksigner_run.addFileArg(b.path("build/debug.keystore"));
    apksigner_run.addArgs(&.{ "--ks-pass", "pass:android", "--out" });

    const final_apk = apksigner_run.addOutputFileArg("zerotty.apk");
    apksigner_run.addFileArg(aligned_apk);

    return final_apk;
}

lib: usize,

const DynamicLibrary = @This();

pub usingnamespace switch (@import("builtin").os.tag) {
    .windows => Win32Loader,
    .linux, .macos => PosixLoader,
    else => {},
};

const Win32Loader = struct {
    const win32 = @import("win32");
    const HINSTANCE = win32.foundation.HINSTANCE;
    const GetProcAddress = win32.system.library_loader.GetProcAddress;
    const LoadLibrary = win32.system.library_loader.LoadLibraryA;
    const FreeLibrary = win32.system.library_loader.FreeLibrary;

    pub fn init(library_name: [*:0]const u8) !DynamicLibrary {
        return .{ .lib = @intFromPtr(LoadLibrary(library_name) orelse return error.CantLoadLibrary) };
    }

    pub fn getProcAddress(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
        return @ptrCast(GetProcAddress(@ptrFromInt(self.lib), name));
    }

    pub fn deinit(self: *const DynamicLibrary) void {
        _ = FreeLibrary(@ptrFromInt(self.lib));
    }
};

const PosixLoader = struct {
    const c = @cImport({
        @cInclude("dlfcn.h");
    });

    pub fn init(library_name: [*:0]const u8) !DynamicLibrary {
        return .{ .lib = @intFromPtr(c.dlopen(library_name, c.RTLD_NOW) orelse return error.FailedToLoadDynamicLibrary) };
    }

    pub fn getProcAddress(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
        return c.dlsym(@ptrFromInt(self.lib), name);
    }

    pub fn deinit(self: *const DynamicLibrary) void {
        _ = c.dlclose(@ptrFromInt(self.lib));
    }
};

test DynamicLibrary {
    const loader = try DynamicLibrary.init(if (@import("builtin").os.tag == .windows) "C:\\Windows\\System32\\opengl32.dll" else "libGL.so.1");
    defer loader.deinit();

    try @import("std").testing.expect(loader.getProcAddress("glBindTexture") != null);
}

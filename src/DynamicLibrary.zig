const DynamicLibrary = @This();

const Win32Loader = struct {
    const win32 = @import("win32");
    const HINSTANCE = win32.foundation.HINSTANCE;
    const GetProcAddress = win32.system.library_loader.GetProcAddress;
    const LoadLibrary = win32.system.library_loader.LoadLibraryA;
    const FreeLibrary = win32.system.library_loader.FreeLibrary;

    pub fn init(library_name: [*:0]const u8) !DynamicLibrary {
        const dll = LoadLibrary(library_name);
        return .{ .lib = dll orelse return error.CantLoadLibrary };
    }

    pub fn getProcAddress(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
        return @ptrCast(GetProcAddress(@ptrCast(self.lib), name));
    }

    pub fn deinit(self: *const DynamicLibrary) void {
        _ = FreeLibrary(@ptrCast(self.lib));
    }
};

const PosixLoader = struct {
    const c = @cImport({
        @cInclude("dlfcn.h");
    });

    pub fn init(library_name: [*:0]const u8) !DynamicLibrary {
        return .{ .lib = c.dlopen(library_name, c.RTLD_NOW) orelse return error.FailedToLoadDynamicLibrary };
    }

    pub fn getProcAddress(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
        return c.dlsym(self.lib, name);
    }

    pub fn deinit(self: *const DynamicLibrary) void {
        _ = c.dlclose(self.lib);
    }
};

const os = @import("builtin").os.tag;
const Loader = switch (os) {
    .windows => Win32Loader,
    .linux, .macos => PosixLoader,
    else => {},
};

lib: *anyopaque,

pub const init = Loader.init;
pub const getProcAddress = Loader.getProcAddress;
pub const deinit = Loader.deinit;

test "Test Loader" {
    const loader = try DynamicLibrary.init("C:\\Windows\\System32\\opengl32.dll");
    defer loader.deinit();

    try @import("std").testing.expect(loader.getProcAddress("glBindTexture") != null);
}

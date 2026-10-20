const std = @import("std");
const DynamicLibrary = @This();

lib: usize,

pub fn init(library_name: [*:0]const u8) !DynamicLibrary {
    return switch (@import("builtin").os.tag) {
        .windows => initWindows(library_name),
        .linux, .macos => initPosix(library_name),
        else => {},
    };
}

pub fn getProcAddress(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
    return switch (@import("builtin").os.tag) {
        .windows => self.getProcAddressWindows(name),
        .linux, .macos => self.getProcAddressPosix(name),
        else => {},
    };
}

pub fn deinit(self: *const DynamicLibrary) void {
    switch (@import("builtin").os.tag) {
        .windows => self.deinitWindows(),
        .linux, .macos => self.deinitPosix(),
        else => {},
    }
}

fn initPosix(library_name: [*:0]const u8) !DynamicLibrary {
    return .{ .lib = @intFromPtr(std.c.dlopen(
        library_name,
        .{ .NOW = true },
    ) orelse return error.FailedToLoadDynamicLibrary) };
}

fn initWindows(library_name: [*:0]const u8) !DynamicLibrary {
    return .{ .lib = @intFromPtr(LoadLibrary(library_name) orelse return error.CantLoadLibrary) };
}

fn getProcAddressWindows(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
    return @ptrCast(GetProcAddress(@ptrFromInt(self.lib), name));
}

fn getProcAddressPosix(self: *const DynamicLibrary, name: [*:0]const u8) ?*const anyopaque {
    return std.c.dlsym(@ptrFromInt(self.lib), name);
}

fn deinitWindows(self: *const DynamicLibrary) void {
    _ = FreeLibrary(@ptrFromInt(self.lib));
}

fn deinitPosix(self: *const DynamicLibrary) void {
    _ = std.c.dlclose(@ptrFromInt(self.lib));
}

const win32 = @import("win32");
const LoadLibrary = win32.system.library_loader.LoadLibraryA;
const GetProcAddress = win32.system.library_loader.GetProcAddress;
const FreeLibrary = win32.system.library_loader.FreeLibrary;

test DynamicLibrary {
    return error.SkipZigTest;
    // const loader = try DynamicLibrary.init("libvulkan.so.1");
    // defer loader.deinit();
    //
    // try @import("std").testing.expect(loader.getProcAddress("glBindTexture") != null);
}

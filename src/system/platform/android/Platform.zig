const std = @import("std");
const c = @import("android_c");
const root = @import("zerotty").system.platform;

const Platform = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Platform {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Platform) void {
    _ = self; // autofix
}

pub fn createWindow(self: *Platform, options: root.WindowOptions) !void {
    _ = options; // autofix
    _ = self; // autofix
}

pub fn getWindowNativeHandles(self: *Platform) !root.WindowNativeHandles {
    return .{ .window = self.window };
}

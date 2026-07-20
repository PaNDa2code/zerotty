const std = @import("std");

const Platform = @This();
pub const Window = @import("Window.zig");

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Platform {
    return .{
        .allocator = allocator,
    };
}

pub const WindowOptions = struct {
    height: u32,
    width: u32,
    title: []const u8,
};

pub fn createWindow(self: *const Platform, options: WindowOptions) !*Window {
    const win = try self.allocator.create(Window);

    win.* = .new(options.title, options.height, options.width);
    try win.open(self.allocator);

    return win;
}


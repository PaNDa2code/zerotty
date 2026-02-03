const OpenGL = @This();

const std = @import("std");
const root = @import("root.zig");
const win = @import("window");

pub const InitError = std.mem.Allocator.Error ||
    error{};

pub fn init(
    alloc: std.mem.Allocator,
    window_handles: win.WindowHandles,
    settings: root.RendererSettings,
) InitError!*OpenGL {
    _ = settings;
    _ = window_handles;
    const self = try alloc.create(OpenGL);

    return self;
}

pub fn deinit(self: *OpenGL) void {
    _ = self; // autofix
}

const Vulkan = @This();

pub const InitError = std.mem.Allocator.Error ||
    error{};

pub fn init(
    alloc: std.mem.Allocator,
    window_handles: win.WindowHandles,
    settings: root.RendererSettings,
) InitError!*Vulkan {
    _ = settings;
    _ = window_handles;
    const self = try alloc.create(Vulkan);

    return self;
}

pub fn deinit(self: *Vulkan) void {
    _ = self; // autofix
}

const std = @import("std");

const root = @import("root.zig");
const core = @import("core");
const win = @import("window");

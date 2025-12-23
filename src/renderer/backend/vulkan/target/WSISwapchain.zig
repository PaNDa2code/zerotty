const WSISwapchain = @This();

pub fn create(allocator: std.mem.Allocator) !*WSISwapchain {
    const self = try allocator.create(WSISwapchain);

    return self;
}

pub fn destroy(self: *WSISwapchain, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub const vtable = Interface.VTable {
    .create = create,
    .destroy = destroy,
};

const std = @import("std");
const vk = @import("vulkan");
const Interface = @import("Interface.zig");

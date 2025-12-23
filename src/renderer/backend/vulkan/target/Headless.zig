const Headless = @This();

pub fn create(allocator: std.mem.Allocator) !*Headless {
    const self = try allocator.create(Headless);

    return self;
}

pub fn destroy(self: *Headless, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub const vtable = Interface.VTable{
    .create = create,
    .destroy = destroy,
};

const std = @import("std");
const vk = @import("vulkan");
const Interface = @import("Interface.zig");

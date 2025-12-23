const WSI = @This();

context: *const Context,

surface: vk.SurfaceKHR,
swap_chain: vk.SwapchainKHR,

images: []vk.Image,
image_views: []vk.ImageView,

extent: vk.Extent2D,
image_format: vk.Format,

// synchronization objects
inflight_fences: []vk.Fence,
render_finished_sems: []vk.Semaphore,
image_avilable_sems: []vk.Semaphore,

pub fn create(
    allocator: std.mem.Allocator,
    context: *const Context,
) !*WSI {
    const self = try allocator.create(WSI);
    errdefer allocator.destroy(self);

    self.context = context;
    return self;
}

pub fn destroy(self: *WSI, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

pub const vtable = Interface.VTable{
    .create = create,
    .destroy = destroy,
};

const std = @import("std");
const vk = @import("vulkan");
const Interface = @import("Interface.zig");
const Context = @import("../core/Context.zig");

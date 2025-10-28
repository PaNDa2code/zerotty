const Sync = @This();

const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const Core = @import("Core.zig");
const SwapChian = @import("SwapChain.zig");

image_available_semaphores: []vk.Semaphore,
render_finished_semaphores: []vk.Semaphore,
in_flight_fences: []vk.Fence,

pub fn init(
    core: *const Core,
    swap_chain: *const SwapChian,
) !Sync {
    const vkd = &core.dispatch.vkd;
    const mem_cb = core.vk_mem.vkAllocatorCallbacks();

    const count = swap_chain.images.len;

    const image_available_semaphores =
        try core.vk_mem.allocator.alloc(vk.Semaphore, count);

    const render_finished_semaphores =
        try core.vk_mem.allocator.alloc(vk.Semaphore, count);

    const in_flight_fences =
        try core.vk_mem.allocator.alloc(vk.Fence, count);

    const semaphore_info = vk.SemaphoreCreateInfo{};

    const fence_info = vk.FenceCreateInfo{
        .flags = .{ .signaled_bit = true },
    };

    for (0..count) |i| {
        render_finished_semaphores[i] =
            try vkd.createSemaphore(core.device, &semaphore_info, &mem_cb);
        image_available_semaphores[i] =
            try vkd.createSemaphore(core.device, &semaphore_info, &mem_cb);
        in_flight_fences[i] =
            try vkd.createFence(core.device, &fence_info, &mem_cb);
    }

    return .{
        .image_available_semaphores = image_available_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,
    };
}

pub fn deinit(self: *const Sync, core: *const Core) void {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    for (
        self.render_finished_semaphores,
        self.image_available_semaphores,
        self.in_flight_fences,
    ) |semaphore1, semaphore2, fence| {
        vkd.destroySemaphore(core.device, semaphore1, &alloc_callbacks);
        vkd.destroySemaphore(core.device, semaphore2, &alloc_callbacks);
        vkd.destroyFence(core.device, fence, &alloc_callbacks);
    }

    core.vk_mem.allocator.free(self.render_finished_semaphores);
    core.vk_mem.allocator.free(self.image_available_semaphores);
    core.vk_mem.allocator.free(self.in_flight_fences);
}

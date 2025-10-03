const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn createSyncObjects(self: *VulkanRenderer, allocator: Allocator) !void {
    const vkd = self.device_wrapper;
    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    const count = self.swap_chain_images.len;

    const render_finished_semaphores =
        try allocator.alloc(vk.Semaphore, count);

    const semaphore_info = vk.SemaphoreCreateInfo{};

    for (0..count) |i| {
        render_finished_semaphores[i] =
            try vkd.createSemaphore(self.device, &semaphore_info, &mem_cb);
    }

    const image_available_semaphore =
        try vkd.createSemaphore(self.device, &semaphore_info, &mem_cb);

    const fence_info = vk.FenceCreateInfo{
        .flags = .{ .signaled_bit = true },
    };

    const in_flight_fence =
        try vkd.createFence(self.device, &fence_info, &mem_cb);

    self.image_available_semaphore = image_available_semaphore;
    self.render_finished_semaphores = render_finished_semaphores;
    self.in_flight_fence = in_flight_fence;
}

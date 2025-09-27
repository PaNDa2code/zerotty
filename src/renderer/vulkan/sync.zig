const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn createSyncObjects(self: *VulkanRenderer) !void {
    const vkd = self.device_wrapper;
    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    const semaphore_info = vk.SemaphoreCreateInfo{};

    const image_available_semaphore =
        try vkd.createSemaphore(self.device, &semaphore_info, &mem_cb);

    const render_finished_semaphore =
        try vkd.createSemaphore(self.device, &semaphore_info, &mem_cb);

    const fence_info = vk.FenceCreateInfo{
        .flags = .{ .signaled_bit = true },
    };

    const in_flight_fence =
        try vkd.createFence(self.device, &fence_info, &mem_cb);

    self.image_available_semaphore = image_available_semaphore;
    self.render_finished_semaphore = render_finished_semaphore;
    self.in_flight_fence = in_flight_fence;
}

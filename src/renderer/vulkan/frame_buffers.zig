const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createFrameBuffers(self: *VulkanRenderer, allocator: Allocator) !void {
    const vkd = self.device_wrapper;
    const frame_buffers_count = self.swap_chain_image_views.len;

    const frame_buffers = try allocator.alloc(vk.Framebuffer, frame_buffers_count);

    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    for (0..frame_buffers_count) |i| {
        const frame_buffer_create_info = vk.FramebufferCreateInfo{
            .render_pass = self.render_pass,
            .attachment_count = 1,
            .p_attachments = &.{self.swap_chain_image_views[i]},
            .width = self.swap_chain_extent.width,
            .height = self.swap_chain_extent.height,
            .layers = 1,
        };

        frame_buffers[i] =
            try vkd.createFramebuffer(self.device, &frame_buffer_create_info, &mem_cb);
    }

    self.frame_buffers = frame_buffers;
}

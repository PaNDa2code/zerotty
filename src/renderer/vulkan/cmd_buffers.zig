const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

const uploadAtlasToStagingBuffer = @import("texture.zig").uploadAtlas;

pub fn allocCmdBuffers(self: *VulkanRenderer, allocator: Allocator) !void {
    self.cmd_buffers = try _allocCmdBuffers(
        allocator,
        self.device_wrapper,
        self.device,
        2,
        self.queue_family_indcies.graphics_family,
        &self.cmd_pool,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn _allocCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    primary_count: usize,
    queue_family_index: u32,
    p_cmd_pool: *vk.CommandPool,
    vk_mem_cb: *const vk.AllocationCallbacks,
) ![]const vk.CommandBuffer {
    const cmd_pool_create_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = queue_family_index,
    };

    const cmd_pool = try vkd.createCommandPool(device, &cmd_pool_create_info, vk_mem_cb);
    errdefer vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);

    const cmd_buffer_alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = cmd_pool,
        .command_buffer_count = @intCast(primary_count),
        .level = .primary,
    };

    const cmd_buffers = try allocator.alloc(vk.CommandBuffer, primary_count);
    errdefer allocator.free(cmd_buffers);

    try vkd.allocateCommandBuffers(device, &cmd_buffer_alloc_info, cmd_buffers.ptr);

    p_cmd_pool.* = cmd_pool;

    return cmd_buffers;
}

pub fn recordCommandBuffer(self: *VulkanRenderer, image_index: usize) !void {
    const vkd = self.device_wrapper;
    const command_buffer = self.cmd_buffers[0];

    const begin_info = vk.CommandBufferBeginInfo{};

    try vkd.beginCommandBuffer(command_buffer, &begin_info);

    const clear_color = vk.ClearValue{
        .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } },
    };

    const render_pass_begin_info = vk.RenderPassBeginInfo{
        .render_pass = self.render_pass,
        .framebuffer = self.frame_buffers[image_index],
        .render_area = .{
            .extent = self.swap_chain_extent,
            .offset = .{ .x = 0, .y = 0 },
        },
        .clear_value_count = 1,
        .p_clear_values = &.{clear_color},
    };

    const regions = [_]vk.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = 0,
        .size = 128,
    }};

    vkd.cmdCopyBuffer(
        command_buffer,
        self.staging_buffer,
        self.vertex_buffer,
        1,
        &regions,
    );

    vkd.cmdBindVertexBuffers(
        command_buffer,
        0,
        2,
        &.{ self.vertex_buffer, self.vertex_buffer },
        &.{ 0, @sizeOf(Vec4(f32)) * 6 },
    );

    vkd.cmdBeginRenderPass(command_buffer, &render_pass_begin_info, .@"inline");

    vkd.cmdBindPipeline(command_buffer, .graphics, self.pipe_line);

    const view_port = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swap_chain_extent.width),
        .height = @floatFromInt(self.swap_chain_extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    vkd.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&view_port));

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swap_chain_extent,
    };

    vkd.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

    vkd.cmdBindDescriptorSets(
        command_buffer,
        .graphics,
        self.pipe_line_layout,
        0,
        1,
        &.{self.descriptor_set},
        0,
        null,
    );

    vkd.cmdDraw(command_buffer, 6, 1, 0, 0);

    vkd.cmdEndRenderPass(command_buffer);

    try vkd.endCommandBuffer(command_buffer);
}

pub fn supmitCmdBuffer(self: *const VulkanRenderer) !void {
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &.{self.cmd_buffers[0]},
    };

    const vkd = self.device_wrapper;

    try vkd.queueSubmit(
        self.graphics_queue,
        1,
        &.{submit_info},
        .null_handle,
    );

    try vkd.queueWaitIdle(self.graphics_queue);

    const present_info = vk.PresentInfoKHR{
        .swapchain_count = 1,
        .p_swapchains = &.{self.swap_chain},
        .p_image_indices = &.{0},
    };

    _ = try vkd.queuePresentKHR(self.present_queue, &present_info);
}
const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

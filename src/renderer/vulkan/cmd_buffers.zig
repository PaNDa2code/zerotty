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

pub fn freeCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    cmd_pool: vk.CommandPool,
    buffers: []const vk.CommandBuffer,
    vk_mem_cb: *const vk.AllocationCallbacks,
) void {
    vkd.freeCommandBuffers(device, cmd_pool, @intCast(buffers.len), buffers.ptr);
    vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);
    allocator.free(buffers);
}

pub fn recordCommandBuffer(self: *VulkanRenderer, image_index: usize) !void {
    const vkd = self.device_wrapper;
    const command_buffer = self.cmd_buffers[0];
    const tex_cmd_buffer = self.cmd_buffers[1];

    const begin_info = vk.CommandBufferBeginInfo{};

    if (self.atlas_dirty) {
        try vkd.beginCommandBuffer(tex_cmd_buffer, &begin_info);

        try uploadAtlasToStagingBuffer(self);

        transitionImageLayout(
            vkd,
            tex_cmd_buffer,
            self.atlas_image,
            .{ .color_bit = true },
            .undefined,
            .transfer_dst_optimal,
        );

        const copy_region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{
                .width = @intCast(self.atlas.width),
                .height = @intCast(self.atlas.height),
                .depth = 1,
            },
        };

        vkd.cmdCopyBufferToImage(
            tex_cmd_buffer,
            self.staging_buffer,
            self.atlas_image,
            .transfer_dst_optimal,
            1,
            &.{copy_region},
        );

        transitionImageLayout(
            vkd,
            tex_cmd_buffer,
            self.atlas_image,
            .{ .color_bit = true },
            .transfer_dst_optimal,
            .shader_read_only_optimal,
        );

        try vkd.endCommandBuffer(tex_cmd_buffer);

        const submit_info = vk.SubmitInfo{
            .s_type = .submit_info,
            .wait_semaphore_count = 0,
            .p_wait_semaphores = null,
            .p_wait_dst_stage_mask = null,
            .command_buffer_count = 1,
            .p_command_buffers = &[_]vk.CommandBuffer{tex_cmd_buffer},
            .signal_semaphore_count = 0,
            .p_signal_semaphores = null,
        };

        try vkd.queueSubmit(self.graphics_queue, 1, &.{submit_info}, vk.Fence.null_handle);
        try vkd.queueWaitIdle(self.graphics_queue);

        self.atlas_dirty = false;
    }

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

pub fn transitionImageLayout(
    vkd: *const vk.DeviceWrapper,
    cmd_buffer: vk.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) void {
    var src_access_mask: vk.AccessFlags = .{};
    var dst_access_mask: vk.AccessFlags = .{};
    var src_stage_mask: vk.PipelineStageFlags = .{};
    var dst_stage_mask: vk.PipelineStageFlags = .{};

    switch (old_layout) {
        .undefined, .preinitialized => {
            src_access_mask = .{};
            src_stage_mask.top_of_pipe_bit = true;
        },
        .transfer_dst_optimal => {
            src_access_mask.transfer_write_bit = true;
            src_stage_mask.transfer_bit = true;
        },
        else => {},
    }

    switch (new_layout) {
        .transfer_dst_optimal => {
            dst_access_mask.transfer_write_bit = true;
            dst_stage_mask.transfer_bit = true;
        },
        .shader_read_only_optimal => {
            dst_access_mask.shader_read_bit = true;
            dst_stage_mask.fragment_shader_bit = true;
        },
        else => {},
    }

    const barrier = vk.ImageMemoryBarrier{
        .s_type = .image_memory_barrier,
        .p_next = null,
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = aspects,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    vkd.cmdPipelineBarrier(
        cmd_buffer,
        src_stage_mask,
        dst_stage_mask,
        .{},
        0,
        null,
        0,
        null,
        1,
        &.{barrier},
    );
}
const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

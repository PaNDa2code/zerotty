const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn drawFrame(self: *const VulkanRenderer) !void {
    const vkd = self.device_wrapper;
    const device = self.device;
    const inflight_fence = self.in_flight_fence;

    const res = try vkd.waitForFences(
        device,
        1,
        &.{inflight_fence},
        .true,
        0,
    );

    if (res == .timeout) return;

    try vkd.resetFences(device, 1, &.{inflight_fence});

    const next_image_index = try nextImage(
        vkd,
        device,
        self.swap_chain,
        self.image_available_semaphore,
    );

    try vkd.resetCommandBuffer(self.cmd_buffers[0], .{});

    try recordCommandBuffer(self, next_image_index);

    try supmitCmdBuffer(self);

    const present_info = vk.PresentInfoKHR{
        .swapchain_count = 1,
        .p_swapchains = &.{self.swap_chain},
        .p_image_indices = &.{next_image_index},

        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{self.render_finished_semaphore},
    };

    _ = try vkd.queuePresentKHR(self.present_queue, &present_info);
}

fn nextImage(
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    swap_chain: vk.SwapchainKHR,
    semaphore: vk.Semaphore,
) !u32 {
    const next_image = try vkd.acquireNextImageKHR(device, swap_chain, std.math.maxInt(u64), semaphore, .null_handle);

    return next_image.image_index;
}

pub fn recordCommandBuffer(
    self: *const VulkanRenderer,
    image_index: usize,
) !void {
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

        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{
            self.image_available_semaphore,
        },
        .p_wait_dst_stage_mask = &.{
            .{ .color_attachment_output_bit = true },
        },

        .signal_semaphore_count = 1,
        .p_signal_semaphores = &.{
            self.render_finished_semaphore,
        },
    };

    const vkd = self.device_wrapper;

    try vkd.queueSubmit(
        self.graphics_queue,
        1,
        &.{submit_info},
        self.in_flight_fence,
    );
}

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

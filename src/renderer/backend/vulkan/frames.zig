const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const Backend = @import("Backend.zig");

pub fn drawFrame(self: *const Backend) !void {
    const vkd = &self.core.dispatch.vkd;
    const device = self.core.device;
    const inflight_fence = self.sync.in_flight_fences[0];

    _ = try vkd.waitForFences(
        device,
        1,
        &.{inflight_fence},
        .true,
        std.math.maxInt(u64),
    );

    try vkd.resetFences(device, 1, &.{inflight_fence});

    const next_image_index = try nextImage(
        vkd,
        device,
        self.swap_chain.handle,
        self.sync.image_available_semaphores[0],
    );

    try vkd.resetCommandBuffer(self.cmd.buffers[0], .{});

    try recordCommandBuffer(self, next_image_index);

    try supmitCmdBuffer(self, next_image_index);

    const present_info = vk.PresentInfoKHR{
        .swapchain_count = 1,
        .p_swapchains = &.{self.swap_chain.handle},
        .p_image_indices = &.{next_image_index},

        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{self.sync.render_finished_semaphores[next_image_index]},
    };

    _ = try vkd.queuePresentKHR(self.core.present_queue, &present_info);
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
    self: *const Backend,
    image_index: usize,
) !void {
    const vkd = &self.core.dispatch.vkd;
    const command_buffer = self.cmd.buffers[0];

    const begin_info = vk.CommandBufferBeginInfo{};

    try vkd.beginCommandBuffer(command_buffer, &begin_info);

    const clear_color = vk.ClearValue{
        .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } },
    };

    const render_pass_begin_info = vk.RenderPassBeginInfo{
        .render_pass = self.pipe_line.render_pass,
        .framebuffer = self.pipe_line.frame_buffers[image_index],
        .render_area = .{
            .extent = self.swap_chain.extent,
            .offset = .{ .x = 0, .y = 0 },
        },
        .clear_value_count = 1,
        .p_clear_values = &.{clear_color},
    };

    const regions = [_]vk.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = 0,
        .size = @sizeOf(@import("../../common/Grid.zig").Cell) * 128,
    }};

    vkd.cmdCopyBuffer(
        command_buffer,
        self.buffers.staging_buffer.handle,
        self.buffers.vertex_buffer.handle,
        regions.len,
        &regions,
    );

    vkd.cmdBindVertexBuffers(
        command_buffer,
        0,
        1,
        &.{self.buffers.vertex_buffer.handle},
        &.{0},
    );

    vkd.cmdBeginRenderPass(command_buffer, &render_pass_begin_info, .@"inline");

    vkd.cmdBindPipeline(command_buffer, .graphics, self.pipe_line.handle);

    const view_port = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swap_chain.extent.width),
        .height = @floatFromInt(self.swap_chain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    vkd.cmdSetViewport(command_buffer, 0, 1, @ptrCast(&view_port));

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swap_chain.extent,
    };

    vkd.cmdSetScissor(command_buffer, 0, 1, @ptrCast(&scissor));

    vkd.cmdBindDescriptorSets(
        command_buffer,
        .graphics,
        self.pipe_line.layout,
        0,
        1,
        &.{self.descriptor.set},
        0,
        null,
    );

    vkd.cmdDraw(command_buffer, 6, 64, 0, 0);

    vkd.cmdEndRenderPass(command_buffer);

    try vkd.endCommandBuffer(command_buffer);
}

pub fn supmitCmdBuffer(self: *const Backend, image_index: usize) !void {
    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &.{self.cmd.buffers[0]},

        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{
            self.sync.image_available_semaphores[0],
        },
        .p_wait_dst_stage_mask = &.{
            .{ .color_attachment_output_bit = true },
        },

        .signal_semaphore_count = 1,
        .p_signal_semaphores = &.{
            self.sync.render_finished_semaphores[image_index],
        },
    };

    const vkd = &self.core.dispatch.vkd;

    try vkd.queueSubmit(
        self.core.graphics_queue,
        1,
        &.{submit_info},
        self.sync.in_flight_fences[0],
    );
}

const math = @import("../../common/math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

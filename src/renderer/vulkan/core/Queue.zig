const Queue = @This();

device: *const Device,

handle: vk.Queue,

index: u32,
family_index: u32,

can_present: bool,

pub fn init(
    device: *const Device,
    index: u32,
    family_index: u32,
    can_present: bool,
) Queue {
    const handle = device.vkd.getDeviceQueue(
        device.handle,
        family_index,
        index,
    );

    return .{
        .device = device,
        .handle = handle,
        .index = index,
        .family_index = family_index,
        .can_present = can_present,
    };
}

pub const SupmitError = vk.DeviceWrapper.QueueSubmitError;

pub fn submit(self: *const Queue, infos: []const vk.SubmitInfo, fence: vk.Fence) SupmitError!void {
    try self.device.vkd.queueSubmit(self.handle, @intCast(infos.len), infos.ptr, fence);
}

pub fn submitOne(
    self: *const Queue,
    cmd: *const CommandBuffer,
    wait_semaphore: vk.Semaphore,
    signal_semaphore: vk.Semaphore,
    wait_stage: vk.PipelineStageFlags,
    fence: vk.Fence,
) SupmitError!void {
    const info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = &.{cmd.handle},
        .p_wait_dst_stage_mask = &.{wait_stage},
        .wait_semaphore_count = if (wait_semaphore == .null_handle) 0 else 1,
        .p_wait_semaphores = &.{wait_semaphore},
        .signal_semaphore_count = if (signal_semaphore == .null_handle) 0 else 1,
        .p_signal_semaphores = &.{signal_semaphore},
    };

    try self.submit(&.{info}, fence);
}

pub const PresentError = error{QueueCannotPresnt} || vk.DeviceWrapper.QueuePresentKHRError;

pub fn present(self: *const Queue, info: *const vk.PresentInfoKHR) PresentError!vk.Result {
    if (!self.can_present)
        return error.QueueCannotPresnt;

    return self.device.vkd.queuePresentKHR(self.handle, info);
}

pub const PresentOneError = PresentError;

pub fn presentOne(
    self: *const Queue,
    swapchain: *const Swapchain,
    wait_semaphore: vk.Semaphore,
    image_index: u32,
) PresentError!vk.Result {
    if (!self.can_present)
        return error.QueueCannotPresnt;

    const info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{wait_semaphore},
        .swapchain_count = 1,
        .p_swapchains = &.{swapchain.handle},
        .p_image_indices = &.{image_index},
    };

    return self.device.vkd.queuePresentKHR(self.handle, &info);
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const CommandBuffer = @import("CommandBuffer.zig");
const Swapchain = @import("Swapchain.zig");

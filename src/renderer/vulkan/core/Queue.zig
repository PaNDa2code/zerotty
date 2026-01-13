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

pub fn supmit(self: *const Queue, infos: []vk.SubmitInfo, fence: vk.Fence) SupmitError!void {
    try self.device.vkd.queueSubmit(self.handle, infos.len, infos.ptr, fence);
}

pub const PresentError = error{QueueCannotPresnt} || vk.DeviceWrapper.QueuePresentKHRError;

pub fn present(self: *const Queue, info: *const vk.PresentInfoKHR) PresentError!vk.Result {
    if (!self.can_present)
        return error.QueueCannotPresnt;

    return self.device.vkd.queuePresentKHR(self.handle, info);
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const CommandBuffer = @import("CommandBuffer.zig");

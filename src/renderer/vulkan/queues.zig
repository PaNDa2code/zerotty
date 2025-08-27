const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");


pub fn getQueues(self: *VulkanRenderer) void {
    self.graphics_queue = self.device_wrapper.getDeviceQueue(self.device, 0, self.queue_family_indcies.graphics_family);
    self.present_queue = self.device_wrapper.getDeviceQueue(self.device, 0, self.queue_family_indcies.present_family);
}

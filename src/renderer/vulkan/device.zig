const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createDevice(
    self: *VulkanRenderer,
    physical_device: vk.PhysicalDevice,
    queue_families_indcies: @import("physical_device.zig").QueueFamilyIndices,
) !void {
    self.device = try _createDevice(
        self.instance_wrapper,
        &self.vk_mem.vkAllocatorCallbacks(),
        physical_device,
        queue_families_indcies,
    );
}

fn _createDevice(
    vki: *const vk.InstanceWrapper,
    vk_mem_cb: *const vk.AllocationCallbacks,
    physical_device: vk.PhysicalDevice,
    queue_families_indcies: @import("physical_device.zig").QueueFamilyIndices,
) !vk.Device {
    const queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = @intCast(queue_families_indcies.graphics_family.?),
        .queue_count = 1,
        .p_queue_priorities = &.{1},
    };

    const ext = [_][*:0]const u8{
        "VK_KHR_swapchain",
    };

    const vald = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const device_features: vk.PhysicalDeviceFeatures = .{};

    const device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = 1,
        .p_queue_create_infos = @ptrCast(&queue_create_info),

        .enabled_extension_count = ext.len,
        .pp_enabled_extension_names = &ext,

        .enabled_layer_count = vald.len,
        .pp_enabled_layer_names = &vald,

        .p_enabled_features = &device_features,
    };

    return try vki.createDevice(physical_device, &device_create_info, vk_mem_cb);
}

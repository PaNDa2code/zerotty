const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");
const build_options = @import("build_options");

const VulkanRenderer = @import("Vulkan.zig");
const QueueFamilyIndices = @import("physical_device.zig").QueueFamilyIndices;

pub fn createDevice(
    self: *VulkanRenderer,
    physical_device: vk.PhysicalDevice,
    queue_families_indcies: QueueFamilyIndices,
) !void {
    errdefer self.device = .null_handle;

    self.device = try _createDevice(
        self.instance_wrapper,
        &self.vk_mem.vkAllocatorCallbacks(),
        physical_device,
        queue_families_indcies,
    );

    self.queue_family_indcies = queue_families_indcies;
}

fn _createDevice(
    vki: *const vk.InstanceWrapper,
    vk_mem_cb: *const vk.AllocationCallbacks,
    physical_device: vk.PhysicalDevice,
    queue_families_indcies: QueueFamilyIndices,
) !vk.Device {
    const queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = queue_families_indcies.graphics_family,
        .queue_count = 1,
        .p_queue_priorities = &.{1},
    };

    const extensions = [_][*:0]const u8{
        "VK_KHR_swapchain",
    };

    const validation_layer_extensions = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const sync2_features =
        vk.PhysicalDeviceSynchronization2Features{
            .synchronization_2 = .true,
        };

    const layer_extensions = [_][*:0]const u8{} ++
        if (build_options.@"renderer-debug") validation_layer_extensions else [_][*:0]const u8{};

    const device_features: vk.PhysicalDeviceFeatures = .{};

    const device_create_info: vk.DeviceCreateInfo = .{
        .p_next = @ptrCast(&sync2_features),

        .queue_create_info_count = 1,
        .p_queue_create_infos = &.{queue_create_info},

        .enabled_extension_count = extensions.len,
        .pp_enabled_extension_names = &extensions,

        .enabled_layer_count = layer_extensions.len,
        .pp_enabled_layer_names = &layer_extensions,

        .p_enabled_features = &device_features,
    };

    return vki.createDevice(physical_device, &device_create_info, vk_mem_cb);
}

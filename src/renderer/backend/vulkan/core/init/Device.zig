const Device = @This();

handle: vk.Device,

physical_device: vk.PhysicalDevice,
physical_device_props: vk.PhysicalDeviceProperties,
physical_device_memory_props: vk.PhysicalDeviceMemoryProperties,

graphic_family_index: u32,
present_family_index: u32,

vkd: vk.DeviceWrapper,

pub const InitError = std.mem.Allocator.Error ||
    vk.InstanceWrapper.enumeratePhysicalDevicesError;

pub fn init(
    allocator: std.mem.Allocator,
    instance: *const Instance,
    surface: ?WsiSurface,
    extensions: [][*:0]const u8,
) InitError!Device {
    const physical_devices =
        try instance.vki.enumeratePhysicalDevicesAlloc(
            instance.handle,
            allocator,
        );

    defer allocator.free(physical_devices);

    std.sort.heap(vk.PhysicalDevice, physical_devices, &instance.vki, physicalDeviceGt);


    return .{};
}

fn physicalDeviceScore(vki: *const vk.InstanceWrapper, physical_device: vk.PhysicalDevice) u32 {
    var score: u32 = 0;
    const device_props = vki.getPhysicalDeviceProperties(physical_device);
    switch (device_props.device_type) {
        // .discrete_gpu => score += 2_000,
        .integrated_gpu => score += 1_000,
        else => {},
    }
    // score += device_props.limits.max_image_dimension_2d;

    return score;
}

fn physicalDeviceGt(vki: *const vk.InstanceWrapper, a: vk.PhysicalDevice, b: vk.PhysicalDevice) bool {
    return physicalDeviceScore(vki, a) > physicalDeviceScore(vki, b);
}

const std = @import("std");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");
const WsiSurface = @import("../../target/Interface.zig").WsiSurface;

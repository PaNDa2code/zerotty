const Device = @This();

handle: vk.Device,

physical_device: vk.PhysicalDevice,
physical_device_props: vk.PhysicalDeviceProperties,
physical_device_memory_props: vk.PhysicalDeviceMemoryProperties,

vkd: vk.DeviceWrapper,

pub fn init() !Device {}

const vk = @import("vulkan");

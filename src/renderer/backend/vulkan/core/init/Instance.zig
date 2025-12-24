const Instance = @This();

handle: vk.Instance,

vkb: vk.BaseWrapper,
vki: vk.InstanceWrapper,

vk_allocator: *const vk.AllocationCallbacks,

debug: vk.DebugUtilsMessengerEXT,

pub fn init() !Instance {}

const vk = @import("vulkan");

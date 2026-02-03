const Frame = @This();

image_index: u32 = 0,

// sync objects
in_flight: vk.Fence = .null_handle,
image_available: vk.Semaphore = .null_handle,
render_finished: vk.Semaphore = .null_handle,

const vk = @import("vulkan");
const core = @import("core");

const Target = @import("Target.zig");

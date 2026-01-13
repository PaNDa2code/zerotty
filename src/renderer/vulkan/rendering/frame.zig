const Frame = struct {
    image: core.Image,

    in_flight: vk.Fence,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
};

const vk = @import("vulkan");
const core = @import("../core/root.zig");

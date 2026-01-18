const Frame = struct {
    image: core.Image,

    in_flight: vk.Fence,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
};

pub fn recordFrame(cmd: *core.CommandBuffer, frame: Frame) !void {
    try cmd.begin(.{ .one_time_submit_bit = true });
}

const vk = @import("vulkan");
const core = @import("../core/root.zig");

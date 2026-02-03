const Target = @This();

image: core.Image,
frame_buffer: core.Framebuffer,

pub fn init(frame_buffer: core.Framebuffer) Target {
    return .{
        .frame_buffer = frame_buffer,
    };
}

pub fn initFromImageView(
    device: *const core.Device,
    render_pass: *const core.RenderPass,
    image_view: vk.ImageView,
    extent: vk.Extent2D,
) Target {
    const frame_buffer = try core.Framebuffer.init(
        device,
        render_pass,
        &.{image_view},
        extent,
    );

    return .{
        .frame_buffer = frame_buffer,
    };
}

pub fn deinit(self: *const Target, device: *const core.Device) void {
    self.frame_buffer.deinit(device);
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");

const Target = @This();

image_view: vk.ImageView,

frame_buffer: core.Framebuffer = .{
    .handle = .null_handle,
    .extent = undefined,
},

pub fn init(image_view: vk.ImageView) Target {
    return .{
        .image_view = image_view,
    };
}

pub fn frameBuffer(
    self: *Target,
    render_pass: *const core.RenderPass,
    extent: vk.Extent2D,
) !core.Framebuffer {
    if (self.frame_buffer.handle != .null_handle and
        self.frame_buffer.extent.height == extent.height and
        self.frame_buffer.extent.width == extent.width)
    {
        return self.frame_buffer;
    }

    self.frame_buffer = try core.Framebuffer.init(
        render_pass.device,
        render_pass,
        &.{self.image_view},
        extent,
    );

    return self.frame_buffer;
}

pub fn deinit(self: *const Target, device: *const core.Device) void {
    self.frame_buffer.deinit(device);
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");

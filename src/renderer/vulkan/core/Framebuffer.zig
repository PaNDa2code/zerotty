const Framebuffer = @This();

handle: vk.Framebuffer,

extent: vk.Extent2D,

pub const InitError = vk.DeviceWrapper.CreateFramebufferError;

pub fn init(
    device: *const Device,
    render_pass: *const RenderPass,
    image_views: []const vk.ImageView,
    extent: vk.Extent2D,
) InitError!Framebuffer {
    const framebuffer_info = vk.FramebufferCreateInfo{
        .render_pass = render_pass.handle,
        .attachment_count = @intCast(image_views.len),
        .p_attachments = image_views.ptr,
        .width = extent.width,
        .height = extent.height,
        .layers = 1,
    };

    const handle = try device.vkd.createFramebuffer(
        device.handle,
        &framebuffer_info,
        device.vk_allocator,
    );

    return .{ .handle = handle, .extent = extent };
}

pub fn deinit(self: *const Framebuffer, device: *const Device) void {
    device.vkd.destroyFramebuffer(device.handle, self.handle, device.vk_allocator);
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const RenderPass = @import("RenderPass.zig");
const RenderTarget = @import("RenderTarget.zig");

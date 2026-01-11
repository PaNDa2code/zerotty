const Framebuffer = @This();

handle: vk.Framebuffer,

extent: vk.Extent2D,

pub const InitError = vk.DeviceWrapper.CreateFramebufferError;

pub fn init(
    device: *const Device,
    render_pass: *const RenderPass,
    render_target: *const RenderTarget,
) InitError!Framebuffer {
    const framebuffer_info = vk.FramebufferCreateInfo{
        .render_pass = render_pass.handle,
        .attachment_count = @intCast(render_target.image_views.len),
        .p_attachments = render_target.image_views.ptr,
        .width = render_target.extent.width,
        .height = render_target.extent.height,
        .layers = 1,
    };

    const handle = try device.vkd.createFramebuffer(
        device.handle,
        &framebuffer_info,
        device.vk_allocator,
    );

    return .{ .handle = handle, .extent = render_target.extent };
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const RenderPass = @import("RenderPass.zig");
const RenderTarget = @import("RenderTarget.zig");

const CommandBuffer = @This();

pool: *const CommandPool,

handle: vk.CommandBuffer,

level: vk.CommandBufferLevel,

// status
recording: bool = false,
owns_handle: bool = false,

pub const InitError = CommandPool.AllocBufferError;

pub fn init(
    pool: *const CommandPool,
    level: vk.CommandBufferLevel,
) InitError!CommandBuffer {
    return pool.allocBuffer(level);
}

pub const BeginError = error{};
pub fn begin(
    self: *const CommandBuffer,
    usage: vk.CommandBufferUsageFlags,
) BeginError!void {
    _ = usage;
    _ = self;
}

pub fn end(self: *const CommandBuffer) void {
    _ = self;
}

pub fn reset(self: *const CommandBuffer) void {
    _ = self;
}

pub fn beginRenderPass(
    self: *const CommandBuffer,
    render_pass: *const RenderPass,
    frame_buffer: vk.Framebuffer,
    clear_values: ?[]vk.ClearValue,
    subpass_contents: vk.SubpassContents,
) void {
    _ = subpass_contents;
    _ = clear_values;
    _ = frame_buffer;
    _ = render_pass;
    _ = self;
}

pub fn endRenderPasss(self: *const CommandBuffer) void {
    _ = self;
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const CommandPool = @import("CommandPool.zig");
const RenderPass = @import("RenderPass.zig");
const FrameBuffer = @import("Framebuffer.zig");

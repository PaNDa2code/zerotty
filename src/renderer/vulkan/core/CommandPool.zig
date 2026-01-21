const CommandPool = @This();

device: *const Device,

handle: vk.CommandPool,

pub const InitError = vk.DeviceWrapper.CreateCommandPoolError;
pub fn init(
    device: *const Device,
    queue_family_index: u32,
) InitError!CommandPool {
    const pool_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = queue_family_index,
    };

    const handle = try device.vkd.createCommandPool(
        device.handle,
        &pool_info,
        device.vk_allocator,
    );

    return .{
        .device = device,
        .handle = handle,
    };
}

pub fn deinit(self: *const CommandPool) void {
    self.device.vkd.destroyCommandPool(
        self.device.handle,
        self.handle,
        self.device.vk_allocator,
    );
}

pub const AllocBuffersError = std.mem.Allocator.Error ||
    vk.DeviceWrapper.AllocateCommandBuffersError;

pub fn allocBuffers(
    self: *const CommandPool,
    allocator: std.mem.Allocator,
    level: vk.CommandBufferLevel,
    count: u32,
) AllocBuffersError![]CommandBuffer {
    const buffer_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.handle,
        .level = level,
        .command_buffer_count = count,
    };

    const handles = try allocator.alloc(vk.CommandBuffer, @intCast(count));
    defer allocator.free(handles);

    try self.device.vkd.allocateCommandBuffers(
        self.device.handle,
        &buffer_info,
        handles.ptr,
    );

    const command_buffers = try allocator.alloc(CommandBuffer, @intCast(count));

    for (command_buffers, handles) |*buffer, handle| {
        buffer.* = .{
            .device = self.device,
            .pool = self,
            .handle = handle,
            .level = level,
        };
    }

    return command_buffers;
}

pub const AllocBufferError = vk.DeviceWrapper.AllocateCommandBuffersError;

pub fn allocBuffer(
    self: *const CommandPool,
    level: vk.CommandBufferLevel,
) AllocBufferError!CommandBuffer {
    const buffer_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.handle,
        .level = level,
        .command_buffer_count = 1,
    };

    var handle = [_]vk.CommandBuffer{.null_handle};

    try self.device.vkd.allocateCommandBuffers(
        self.device.handle,
        &buffer_info,
        &handle,
    );

    return .{
        .device = self.device,
        .pool = self,
        .handle = handle[0],
        .level = level,
    };
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const CommandBuffer = @import("CommandBuffer.zig");

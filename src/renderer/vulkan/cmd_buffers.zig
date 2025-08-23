const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn allocCmdBuffers(self: *VulkanRenderer, allocator: Allocator) !void {
    self.cmd_buffers = try _allocCmdBuffers(
        allocator,
        self.device_wrapper,
        self.device,
        1,
        &self.cmd_pool,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn _allocCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    primary_count: usize,
    p_cmd_pool: *vk.CommandPool,
    vk_mem_cb: *const vk.AllocationCallbacks,
) ![]const vk.CommandBuffer {
    const cmd_pool_create_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = 0,
    };

    const cmd_pool = try vkd.createCommandPool(device, &cmd_pool_create_info, vk_mem_cb);
    errdefer vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);

    const cmd_buffer_alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = cmd_pool,
        .command_buffer_count = @intCast(primary_count),
        .level = .primary,
    };

    const cmd_buffers = try allocator.alloc(vk.CommandBuffer, primary_count);
    errdefer allocator.free(cmd_buffers);

    try vkd.allocateCommandBuffers(device, &cmd_buffer_alloc_info, cmd_buffers.ptr);

    p_cmd_pool.* = cmd_pool;

    return cmd_buffers;
}

pub fn freeCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    cmd_pool: vk.CommandPool,
    buffers: []const vk.CommandBuffer,
    vk_mem_cb: *const vk.AllocationCallbacks,
) void {
    vkd.freeCommandBuffers(device, cmd_pool, @intCast(buffers.len), buffers.ptr);
    vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);
    allocator.free(buffers);
}

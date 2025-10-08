const Command = @This();

const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const Core = @import("Core.zig");

pool: vk.CommandPool,
buffers: []vk.CommandBuffer,

pub fn init(core: *const Core, primary_count: usize) !Command {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const cmd_pool_create_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = core.graphics_family_index,
    };

    const cmd_pool = try vkd.createCommandPool(
        core.device,
        &cmd_pool_create_info,
        &alloc_callbacks,
    );
    errdefer vkd.destroyCommandPool(
        core.device,
        cmd_pool,
        &alloc_callbacks,
    );

    const cmd_buffer_alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = cmd_pool,
        .command_buffer_count = @intCast(primary_count),
        .level = .primary,
    };

    const cmd_buffers =
        try core.vk_mem.allocator.alloc(
            vk.CommandBuffer,
            primary_count,
        );
    errdefer core.vk_mem.allocator.free(cmd_buffers);

    try vkd.allocateCommandBuffers(
        core.device,
        &cmd_buffer_alloc_info,
        cmd_buffers.ptr,
    );

    return .{
        .pool = cmd_pool,
        .buffers = cmd_buffers,
    };
}

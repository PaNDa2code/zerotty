const Descriptor = @This();

const std = @import("std");
const vk = @import("vulkan");
const Core = @import("Core.zig");

set: vk.DescriptorSet,

layout: vk.DescriptorSetLayout,

pool: vk.DescriptorPool,

pub fn init(core: *const Core) !Descriptor {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
    };

    const set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    };

    const layout = try vkd.createDescriptorSetLayout(
        core.device,
        &set_layout_info,
        &alloc_callbacks,
    );

    const uniform_descriptor_pool_size = vk.DescriptorPoolSize{
        .type = .uniform_buffer,
        .descriptor_count = 1,
    };

    const sampled_image_descriptor_pool_size = vk.DescriptorPoolSize{
        .type = .combined_image_sampler,
        .descriptor_count = 1,
    };

    const descriptor_pool_info = vk.DescriptorPoolCreateInfo{
        .max_sets = 1,
        .pool_size_count = 2,
        .p_pool_sizes = &.{
            uniform_descriptor_pool_size,
            sampled_image_descriptor_pool_size,
        },
    };

    const pool = try vkd.createDescriptorPool(
        core.device,
        &descriptor_pool_info,
        &alloc_callbacks,
    );

    const descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &.{layout},
    };

    var set: vk.DescriptorSet = .null_handle;

    try vkd.allocateDescriptorSets(
        core.device,
        &descriptor_set_alloc_info,
        @ptrCast(&set),
    );

    return .{
        .set = set,
        .layout = layout,
        .pool = pool,
    };
}

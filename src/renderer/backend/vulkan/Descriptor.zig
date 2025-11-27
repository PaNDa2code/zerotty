const Descriptor = @This();

const std = @import("std");
const vk = @import("vulkan");
const Core = @import("Core.zig");
const Buffers = @import("Buffers.zig");

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
        .{
            .binding = 2,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
        },
        .{
            .binding = 3,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
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

    const glyph_ssbo_pool_size = vk.DescriptorPoolSize{
        .type = .storage_buffer,
        .descriptor_count = 1,
    };

    const style_ssbo_pool_size = vk.DescriptorPoolSize{
        .type = .storage_buffer,
        .descriptor_count = 1,
    };

    const descriptor_pool_info = vk.DescriptorPoolCreateInfo{
        .max_sets = 1,
        .pool_size_count = 4,
        .p_pool_sizes = &.{
            uniform_descriptor_pool_size,
            sampled_image_descriptor_pool_size,
            glyph_ssbo_pool_size,
            style_ssbo_pool_size,
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

pub fn deinit(
    self: *const Descriptor,
    core: *const Core,
) void {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    vkd.destroyDescriptorSetLayout(core.device, self.layout, &alloc_callbacks);
    vkd.destroyDescriptorPool(core.device, self.pool, &alloc_callbacks);
}

pub fn updateDescriptorSets(
    self: *const Descriptor,
    core: *const Core,
    buffers: *const Buffers,
    atlas_view: vk.ImageView,
    atlas_sampler: vk.Sampler,
) !void {
    const vkd = &core.dispatch.vkd;

    const uniform_block_buffer_info = vk.DescriptorBufferInfo{
        .buffer = buffers.uniform_buffer.handle,
        .offset = 0,
        .range = @sizeOf(Buffers.UniformsBlock),
    };

    const uniform_block_write = vk.WriteDescriptorSet{
        .dst_set = self.set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .descriptor_type = .uniform_buffer,
        .descriptor_count = 1,
        .p_buffer_info = &.{uniform_block_buffer_info},
        .p_image_info = &.{},
        .p_texel_buffer_view = &.{},
    };

    const image_info = vk.DescriptorImageInfo{
        .image_layout = .read_only_optimal,
        .image_view = atlas_view,
        .sampler = atlas_sampler,
    };

    const image_write = vk.WriteDescriptorSet{
        .dst_set = self.set,
        .dst_binding = 1,
        .dst_array_element = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .p_buffer_info = &.{},
        .p_image_info = &.{image_info},
        .p_texel_buffer_view = &.{},
    };

    const glyph_ssbo_info = vk.DescriptorBufferInfo{
        .buffer = buffers.glyph_ssbo.handle,
        .offset = 0,
        .range = @intCast(buffers.glyph_ssbo.memory.size),
    };

    const glyph_ssbo_write = vk.WriteDescriptorSet{
        .dst_set = self.set,
        .dst_binding = 2,
        .dst_array_element = 0,
        .descriptor_type = .storage_buffer,
        .descriptor_count = 1,
        .p_buffer_info = &.{glyph_ssbo_info},
        .p_image_info = &.{},
        .p_texel_buffer_view = &.{},
    };

    const style_ssbo_info = vk.DescriptorBufferInfo{
        .buffer = buffers.style_ssbo.handle,
        .offset = 0,
        .range = @intCast(buffers.style_ssbo.memory.size),
    };

    const style_ssbo_write = vk.WriteDescriptorSet{
        .dst_set = self.set,
        .dst_binding = 3,
        .dst_array_element = 0,
        .descriptor_type = .storage_buffer,
        .descriptor_count = 1,
        .p_buffer_info = &.{style_ssbo_info},
        .p_image_info = &.{},
        .p_texel_buffer_view = &.{},
    };

    const writes = [_]vk.WriteDescriptorSet{
        uniform_block_write,
        image_write,
        glyph_ssbo_write,
        style_ssbo_write,
    };

    vkd.updateDescriptorSets(core.device, writes.len, &writes, 0, null);
}

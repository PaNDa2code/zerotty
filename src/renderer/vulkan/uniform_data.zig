const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const Core = @import("Core.zig");
const Buffers = @import("Buffers.zig");
const Descriptor = @import("Descriptor.zig");

const UniformsBlock = @import("Buffers.zig").UniformsBlock;

pub fn updateDescriptorSets(
    core: *const Core,
    descriptor: *const Descriptor,
    buffers: *const Buffers,
    atlas_view: vk.ImageView,
    atlas_sampler: vk.Sampler,
) !void {
    const vkd = &core.dispatch.vkd;

    const uniform_block_buffer_info = vk.DescriptorBufferInfo{
        .buffer = buffers.uniform_buffer.handle,
        .offset = 0,
        .range = @sizeOf(UniformsBlock),
    };

    const uniform_block_write = vk.WriteDescriptorSet{
        .dst_set = descriptor.set,
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
        .dst_set = descriptor.set,
        .dst_binding = 1,
        .dst_array_element = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .p_buffer_info = &.{},
        .p_image_info = &.{image_info},
        .p_texel_buffer_view = &.{},
    };

    const writes = [_]vk.WriteDescriptorSet{ uniform_block_write, image_write };
    vkd.updateDescriptorSets(core.device, writes.len, &writes, 0, null);
}

/// set ubo values
pub fn updateUniformData(
    core: *const Core,
    buffers: *const Buffers,
    data: *const UniformsBlock,
) !void {
    const vkd = &core.dispatch.vkd;

    const ptr = try vkd.mapMemory(
        core.device,
        buffers.uniform_buffer.memory,
        0,
        @sizeOf(UniformsBlock),
        .{},
    );
    defer vkd.unmapMemory(core.device, buffers.uniform_buffer.memory);

    @as(*UniformsBlock, @ptrCast(@alignCast(ptr))).* = data.*;
    // @as(*UniformsBlock, @ptrCast(@alignCast(ptr))).* = .{
    //     .cell_height = @floatFromInt(self.atlas.cell_height),
    //     .cell_width = @floatFromInt(self.atlas.cell_width),
    //     .screen_height = @floatFromInt(self.window_height),
    //     .screen_width = @floatFromInt(self.window_width),
    //     .atlas_cols = @floatFromInt(self.atlas.cols),
    //     .atlas_rows = @floatFromInt(self.atlas.rows),
    //     .atlas_height = @floatFromInt(self.atlas.height),
    //     .atlas_width = @floatFromInt(self.atlas.width),
    //     .descender = @floatFromInt(self.atlas.descender),
    // };
}

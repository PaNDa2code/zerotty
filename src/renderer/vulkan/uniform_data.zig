const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

const UniformsBlock = @import("Buffers.zig").UniformsBlock;

pub fn updateDescriptorSets(self: *VulkanRenderer) !void {
    const vkd = self.device_wrapper;

    const uniform_block_buffer_info = vk.DescriptorBufferInfo{
        .buffer = self.uniform_buffer,
        .offset = 0,
        .range = @sizeOf(UniformsBlock),
    };

    const uniform_block_write = vk.WriteDescriptorSet{
        .dst_set = self.descriptor_set,
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
        .image_view = self.atlas_image_view,
        .sampler = self.atlas_sampler,
    };

    const image_write = vk.WriteDescriptorSet{
        .dst_set = self.descriptor_set,
        .dst_binding = 1,
        .dst_array_element = 0,
        .descriptor_type = .combined_image_sampler,
        .descriptor_count = 1,
        .p_buffer_info = &.{},
        .p_image_info = &.{image_info},
        .p_texel_buffer_view = &.{},
    };

    const writes = [_]vk.WriteDescriptorSet{ uniform_block_write, image_write };
    vkd.updateDescriptorSets(self.device, writes.len, &writes, 0, null);
}

pub fn updateUniformData(self: *const VulkanRenderer) !void {
    const vkd = self.device_wrapper;

    const ptr = try vkd.mapMemory(
        self.device,
        self.uniform_memory,
        0,
        @sizeOf(UniformsBlock),
        .{},
    );

    @as(*UniformsBlock, @ptrCast(@alignCast(ptr))).* = .{
        .cell_height = @floatFromInt(self.atlas.cell_height),
        .cell_width = @floatFromInt(self.atlas.cell_width),
        .screen_height = @floatFromInt(self.window_height),
        .screen_width = @floatFromInt(self.window_width),
        .atlas_cols = @floatFromInt(self.atlas.cols),
        .atlas_rows = @floatFromInt(self.atlas.rows),
        .atlas_height = @floatFromInt(self.atlas.height),
        .atlas_width = @floatFromInt(self.atlas.width),
        .descender = @floatFromInt(self.atlas.descender),
    };

    vkd.unmapMemory(self.device, self.uniform_memory);
}


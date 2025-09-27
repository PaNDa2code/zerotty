const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn updateUniformData(self: *VulkanRenderer) !void {
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

const UniformsBlock = @import("vertex_buffer.zig").UniformsBlock;

const std = @import("std");

const vk = @import("vulkan");

const VulkanRenderer = @import("Vulkan.zig");

fn createDescriptorSetLayout(
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.DescriptorSetLayout {
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

    const descriptor_set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    };

    return vkd.createDescriptorSetLayout(device, &descriptor_set_layout_info, vkmemcb);
}

pub fn createDescriptorSet(self: *VulkanRenderer) !void {
    const vkd = self.device_wrapper;
    const memcb = self.vk_mem.vkAllocatorCallbacks();

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

    const descriptor_set_layout = try createDescriptorSetLayout(vkd, self.device, &memcb);

    const descriptor_pool = try vkd.createDescriptorPool(self.device, &descriptor_pool_info, &memcb);

    const descriptor_set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = descriptor_pool,
        .descriptor_set_count = 1,
        .p_set_layouts = &.{descriptor_set_layout},
    };

    var descriptor_set: vk.DescriptorSet = .null_handle;
    try vkd.allocateDescriptorSets(self.device, &descriptor_set_alloc_info, @ptrCast(&descriptor_set));

    self.descriptor_set_layout = descriptor_set_layout;
    self.descriptor_pool = descriptor_pool;
    self.descriptor_set = descriptor_set;
}

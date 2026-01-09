const DescriptorSet = @This();

handle: vk.DescriptorSet,

pool: *const DescriptorPool,
layout: *const DescriptorSetLayout,

// TODO: use maps
// [binding][element]
buffer_infos: [][]vk.DescriptorBufferInfo,
image_infos: [][]vk.DescriptorImageInfo,

allocator: std.mem.Allocator,
write_descriptor_sets: std.ArrayList(vk.WriteDescriptorSet),

pub const InitError = std.mem.Allocator.Error ||
    vk.DeviceWrapper.AllocateDescriptorSetsError;

pub fn init(
    pool: *const DescriptorPool,
    layout: *const DescriptorSetLayout,
    allocator: std.mem.Allocator,
    buffer_infos: [][]vk.DescriptorBufferInfo,
    image_infos: [][]vk.DescriptorImageInfo,
) InitError!DescriptorSet {
    const handle = try pool.allocDescriptorSets(layout);

    var self = DescriptorSet{
        .handle = handle,
        .pool = pool,
        .layout = layout,
        .buffer_infos = buffer_infos,
        .image_infos = image_infos,
        .allocator = allocator,
        .write_descriptor_sets = .empty,
    };

    try self.prepare();

    return self;
}

pub const ResetError = error{};

pub fn reset(
    self: *DescriptorSet,
    buffer_infos: [][]vk.DescriptorBufferInfo,
    image_infos: [][]vk.DescriptorImageInfo,
) !void {
    if (buffer_infos.len != 0 and image_infos != 0) {
        self.image_infos = image_infos;
        self.buffer_infos = buffer_infos;
    }

    self.write_descriptor_sets.clearRetainingCapacity();

    self.prepare();
}

pub fn prepare(self: *DescriptorSet) std.mem.Allocator.Error!void {
    const limits = self.pool.context.gpu_props.limits;

    for (self.buffer_infos, 0..) |binding_buffers, binding_index| {
        const layout_binding = self.layout.bindings[binding_index];
        for (binding_buffers, 0..) |*buffer_info, array_index| {
            var range = buffer_info.range;

            switch (layout_binding.descriptor_type) {
                .uniform_buffer, .uniform_buffer_dynamic => {
                    if (range > limits.max_uniform_buffer_range)
                        range = limits.max_uniform_buffer_range;
                },
                .storage_buffer, .storage_buffer_dynamic => {
                    if (range > limits.max_storage_buffer_range)
                        range = limits.max_storage_buffer_range;
                },
                else => {},
            }

            buffer_info.range = range;
            try self.write_descriptor_sets.append(self.allocator, .{
                .dst_set = self.handle,
                .dst_binding = @intCast(binding_index),
                .dst_array_element = @intCast(array_index),
                .descriptor_count = 1,
                .descriptor_type = layout_binding.descriptor_type,
                .p_buffer_info = @ptrCast(buffer_info),
                .p_image_info = &.{},
                .p_texel_buffer_view = &.{},
            });
        }
    }

    for (self.image_infos, 0..) |binding_images, binding_index| {
        const layout_binding = self.layout.bindings[binding_index];
        for (binding_images, 0..) |*image_info, array_index| {
            try self.write_descriptor_sets.append(self.allocator, .{
                .dst_set = self.handle,
                .dst_binding = @intCast(binding_index),
                .dst_array_element = @intCast(array_index),
                .descriptor_count = 1,
                .descriptor_type = layout_binding.descriptor_type,
                .p_image_info = @ptrCast(image_info),
                .p_buffer_info = &.{},
                .p_texel_buffer_view = &.{},
            });
        }
    }
}

pub fn update(self: *DescriptorSet) void {
    self.pool.context.vkd.updateDescriptorSets(
        self.pool.context.device,
        @intCast(self.write_descriptor_sets.items.len),
        self.write_descriptor_sets.items.ptr,
        0,
        null,
    );

    self.write_descriptor_sets.clearRetainingCapacity();
}

const std = @import("std");
const vk = @import("vulkan");

const DescriptorPool = @import("DescriptorPool.zig");
const DescriptorSetLayout = @import("DescriptorSetLayout.zig");

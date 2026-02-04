const DescriptorSet = @This();

handle: vk.DescriptorSet,

pool: *const DescriptorPool,
layout: *const DescriptorSetLayout,

// [binding][element]
buffer_infos: *const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)),
image_infos: *const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)),

allocator: std.mem.Allocator,
write_descriptor_sets: std.ArrayList(vk.WriteDescriptorSet),

pub const InitError = std.mem.Allocator.Error ||
    vk.DeviceWrapper.AllocateDescriptorSetsError;

pub fn init(
    pool: *const DescriptorPool,
    layout: *const DescriptorSetLayout,
    allocator: std.mem.Allocator,
    buffer_infos: *const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)),
    image_infos: *const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)),
) InitError!DescriptorSet {
    const handle = try pool.allocDescriptorSet(layout);

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
    buffer_infos: ?*const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)),
    image_infos: ?*const std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)),
) !void {
    self.image_infos.clearRetainingCapacity();
    self.buffer_infos.clearRetainingCapacity();

    if (buffer_infos != null and image_infos != null) {
        self.image_infos = image_infos;
        self.buffer_infos = buffer_infos;
    }

    self.write_descriptor_sets.clearRetainingCapacity();

    try self.prepare();
}

pub fn prepare(self: *DescriptorSet) std.mem.Allocator.Error!void {
    const limits = self.pool.device.physical_device.properties.limits;

    var buffers_iter = self.buffer_infos.iterator();

    while (buffers_iter.next()) |entry| {
        const binding_index = entry.key_ptr.*;
        const layout_binding = self.layout.bindings[binding_index];

        for (entry.value_ptr.items, 0..) |*buffer_info, array_index| {
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

    var images_iter = self.image_infos.iterator();

    while (images_iter.next()) |entry| {
        const binding_index = entry.key_ptr.*;
        const layout_binding = self.layout.bindings[binding_index];
        for (entry.value_ptr.items, 0..) |*image_info, array_index| {
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
    self.pool.device.vkd.updateDescriptorSets(
        self.pool.device.handle,
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

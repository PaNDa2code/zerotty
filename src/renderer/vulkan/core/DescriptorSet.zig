const DescriptorSet = @This();

pub const DescriptorPostion = struct {
    binding: u32,
    array_element: u32 = 0,
};

pub const DescriptorInfo = union(enum) {
    buffer: vk.DescriptorBufferInfo,
    image: vk.DescriptorImageInfo,
};

handle: vk.DescriptorSet,

pool: *const DescriptorPool,
layout: *const DescriptorSetLayout,

descriptors: std.AutoHashMapUnmanaged(DescriptorPostion, DescriptorInfo),

allocator: std.mem.Allocator,
write_descriptor_sets: std.ArrayList(vk.WriteDescriptorSet),

pub const InitError = std.mem.Allocator.Error ||
    vk.DeviceWrapper.AllocateDescriptorSetsError;

pub fn init(
    pool: *const DescriptorPool,
    layout: *const DescriptorSetLayout,
    allocator: std.mem.Allocator,
) InitError!DescriptorSet {
    const handle = try pool.allocDescriptorSet(layout);

    var self = DescriptorSet{
        .handle = handle,
        .pool = pool,
        .layout = layout,
        .descriptors = .empty,
        .allocator = allocator,
        .write_descriptor_sets = .empty,
    };

    try self.prepare();

    return self;
}

pub fn deinit(self: *DescriptorSet) void {
    self.descriptors.deinit(self.allocator);
    self.write_descriptor_sets.deinit(self.allocator);
}

pub fn addDescriptor(
    self: *DescriptorSet,
    binding: u32,
    array_element: u32,
    info: DescriptorInfo,
) !void {
    try self.descriptors.put(
        self.allocator,
        .{
            .binding = binding,
            .array_element = array_element,
        },
        info,
    );
}

pub const ResetError = error{};

pub fn reset(
    self: *DescriptorSet,
) !void {
    self.write_descriptor_sets.clearRetainingCapacity();
    try self.prepare();
}

pub fn prepare(self: *DescriptorSet) std.mem.Allocator.Error!void {
    const limits = self.pool.device.physical_device.properties.limits;

    var desc_iter = self.descriptors.iterator();

    while (desc_iter.next()) |entry| {
        const position = entry.key_ptr.*;
        var info_ptr = entry.value_ptr;

        const layout_binding = self.layout.bindings[position.binding];

        switch (info_ptr.*) {
            .buffer => {
                var range = info_ptr.buffer.range;

                switch (layout_binding.descriptor_type) {
                    .uniform_buffer, .uniform_buffer_dynamic => {
                        range = @min(range, limits.max_uniform_buffer_range);
                    },
                    .storage_buffer, .storage_buffer_dynamic => {
                        range = @min(range, limits.max_storage_buffer_range);
                    },
                    else => {},
                }

                info_ptr.buffer.range = range;

                try self.write_descriptor_sets.append(self.allocator, .{
                    .dst_set = self.handle,
                    .dst_binding = position.binding,
                    .dst_array_element = position.array_element,
                    .descriptor_count = 1,
                    .descriptor_type = layout_binding.descriptor_type,
                    .p_buffer_info = @ptrCast(&info_ptr.buffer),
                    .p_image_info = &.{},
                    .p_texel_buffer_view = &.{},
                });
            },
            .image => {
                try self.write_descriptor_sets.append(self.allocator, .{
                    .dst_set = self.handle,
                    .dst_binding = position.binding,
                    .dst_array_element = position.array_element,
                    .descriptor_count = 1,
                    .descriptor_type = layout_binding.descriptor_type,
                    .p_image_info = @ptrCast(&info_ptr.image),
                    .p_buffer_info = &.{},
                    .p_texel_buffer_view = &.{},
                });
            },
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

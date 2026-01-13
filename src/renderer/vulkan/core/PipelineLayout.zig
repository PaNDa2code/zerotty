const PipelineLayout = @This();

handle: vk.PipelineLayout,

pub const InitError = vk.DeviceWrapper.CreatePipelineLayoutError ||
    std.mem.Allocator.Error;

pub fn init(
    device: *const Device,
    descriptor_set_layouts: []const DescriptorSetLayout,
    allocator: std.mem.Allocator,
) InitError!PipelineLayout {
    const descriptor_set_layout_handles = try allocator.alloc(
        vk.DescriptorSetLayout,
        descriptor_set_layouts.len,
    );
    defer allocator.free(descriptor_set_layout_handles);

    for (0..descriptor_set_layouts.len) |i| {
        descriptor_set_layout_handles[i] = descriptor_set_layouts[i].handle;
    }

    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = @intCast(descriptor_set_layout_handles.len),
        .p_set_layouts = descriptor_set_layout_handles.ptr,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    const handle = try device.vkd.createPipelineLayout(
        device.handle,
        &pipeline_layout_info,
        device.vk_allocator,
    );

    return .{ .handle = handle };
}

pub fn deinit(self: *const PipelineLayout, device: *const Device) void {
    device.vkd.destroyPipelineLayout(
        device.handle,
        self.handle,
        device.vk_allocator,
    );
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const DescriptorSetLayout = @import("DescriptorSetLayout.zig");

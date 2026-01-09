const DescriptorSetLayout = @This();

handle: vk.DescriptorSetLayout,
bindings: []const vk.DescriptorSetLayoutBinding,

pub const Builder = DescriptorSetLayoutBuilder(&.{});

fn DescriptorSetLayoutBuilder(
    comptime Bindings: []const vk.DescriptorSetLayoutBinding,
) type {
    return struct {
        pub fn addBinding(
            comptime binding: comptime_int,
            comptime descriptor_type: vk.DescriptorType,
            comptime descriptor_count: comptime_int,
            comptime stage_flags: vk.ShaderStageFlags,
        ) type {
            return DescriptorSetLayoutBuilder(Bindings ++ &[_]vk.DescriptorSetLayoutBinding{.{
                .binding = binding,
                .descriptor_type = descriptor_type,
                .descriptor_count = descriptor_count,
                .stage_flags = stage_flags,
            }});
        }

        pub fn build(
            device: *const Device,
        ) InitError!DescriptorSetLayout {
            return DescriptorSetLayout.init(device, Bindings);
        }
    };
}

pub const InitError = vk.DeviceWrapper.CreateDescriptorSetLayoutError;

pub fn init(
    device: *const Device,
    bindings: []const vk.DescriptorSetLayoutBinding,
) InitError!DescriptorSetLayout {
    const descriptor_set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(bindings.len),
        .p_bindings = bindings.ptr,
    };

    const descriptor_set_layout =
        try device.vkd.createDescriptorSetLayout(
            device.handle,
            &descriptor_set_layout_info,
            device.vk_allocator,
        );

    return .{
        .handle = descriptor_set_layout,
        .bindings = bindings,
    };
}

pub fn deinit(
    self: *const DescriptorSetLayout,
    device: *const Device,
) void {
    device.vkd.destroyDescriptorSetLayout(
        device.handle,
        self.handle,
        device.vk_allocator,
    );
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");

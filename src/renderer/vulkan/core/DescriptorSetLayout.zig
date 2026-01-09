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

        pub fn build(context: *const Context) InitError!DescriptorSetLayout {
            return DescriptorSetLayout.init(context, Bindings);
        }
    };
}

pub const InitError = vk.DeviceWrapper.CreateDescriptorSetLayoutError;

pub fn init(
    context: *const Context,
    bindings: []const vk.DescriptorSetLayoutBinding,
) InitError!DescriptorSetLayout {
    const descriptor_set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(bindings.len),
        .p_bindings = bindings.ptr,
    };

    const descriptor_set_layout =
        try context.vkd.createDescriptorSetLayout(
            context.device,
            &descriptor_set_layout_info,
            context.vk_allocator,
        );

    return .{
        .handle = descriptor_set_layout,
        .bindings = bindings,
    };
}

pub fn deinit(self: *const DescriptorSetLayout, context: *const Context) void {
    context.vkd.destroyDescriptorSetLayout(
        context.device,
        self.handle,
        context.vk_allocator,
    );
}

const std = @import("std");
const vk = @import("vulkan");
const Context = @import("Context.zig");

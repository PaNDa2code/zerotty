//! Shared renderer context.
//!
//! This owns the Vulkan instance/device and related stuff.
//! Most of the renderer ends up depending on this.
const Context = @This();

device: vk.Device,
instance: vk.Instance,

gpu: vk.PhysicalDevice,
gpu_props: vk.PhysicalDeviceProperties,
gpu_memory_props: vk.PhysicalDeviceMemoryProperties,

// dispatch tables
vkb: vk.BaseWrapper,
vki: vk.InstanceWrapper,
vkd: vk.DeviceWrapper,

// allocation callbacks
vk_allocator: ?*const vk.AllocationCallbacks,

debug_messanger: if (builtin.mode == .Debug) vk.DebugUtilsMessengerEXT else void,

pub fn init(
    allocator: std.mem.Allocator,
    instance: Instance,
    device: Device,
) !*const Context {
    const context = try allocator.create(Context);
    errdefer allocator.destroy(context);

    context.* = .{
        .instance = instance.handle,
        .device = device.handle,

        .gpu = device.physical_device.handle,
        .gpu_props = device.physical_device.properties,
        .gpu_memory_props = device.physical_device.memory_properties,

        // TODO: eliminate this table copying
        .vkb = instance.vkb,
        .vki = instance.vki,
        .vkd = device.vkd,

        .vk_allocator = instance.vk_allocator,

        .debug_messanger = instance.debug,
    };

    return context;
}

pub fn deinit(self: *const Context, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const utils = @import("init/root.zig");

pub const Instance = @import("init/Instance.zig");
pub const Device = @import("init/Device.zig");

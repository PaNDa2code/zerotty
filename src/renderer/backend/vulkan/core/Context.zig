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

// queue_families: QueueFamilies,

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

        .gpu = device.physical_device,
        .gpu_props = device.physical_device_props,
        .gpu_memory_props = device.physical_device_memory_props,

        // TODO: elemnate this table copying
        .vkb = instance.vkb,
        .vki = instance.vki,
        .vkd = device.vkd,

        .vk_allocator = instance.vk_allocator,

        .debug_messanger = instance.debug,
    };

    return context;
}

pub fn createInstance(self: *const Context) !void {
    self.vkb = vk.BaseWrapper.load(struct {
        pub fn load(
            _: vk.Instance,
            procname: [*:0]const u8,
        ) vk.PfnVoidFunction {
            const vk_lib_path: [*:0]const u8 = switch (builtin.os.tag) {
                .windows => "C:\\Windows\\System32\\vulkan-1.dll",
                .linux => "libvulkan.so.1",
                else => {},
            };
            const lib = std.DynLib.openZ(vk_lib_path) catch unreachable;
            const symbol = lib.lookup(*anyopaque, std.mem.span(procname));

            return @ptrCast(symbol);
        }
    });

    self.instance = utils.instance.createInstance(
        &self.vkb,
        // allocator,
        self.vk_allocator,
    );

    self.vki = vk.InstanceWrapper.load(
        self.instance,
        self.vkb.dispatch.vkGetInstanceProcAddr.?,
    );

    errdefer self.vki.destroyInstance(self.instance);

    if (builtin.mode == .Debug) {
        self.debug_messanger =
            try utils.debug.debugMessenger(
                &self.vki,
                self.instance,
                self.vk_allocator,
            );
    }

    return self;
}

pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const utils = @import("init/root.zig");

const QueueFamilies = opaque {};

pub const Instance = @import("init/Instance.zig");
pub const Device = @import("init/Device.zig");

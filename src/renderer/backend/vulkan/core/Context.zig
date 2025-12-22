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

surface: vk.SurfaceKHR,
queue_families: QueueFamilies,

// dispatch tables
vkb: vk.BaseWrapper,
vki: vk.InstanceWrapper,
vkd: vk.DeviceWrapper,

// allocation callbacks
vk_allocator: ?*const vk.AllocationCallbacks,

debug_messanger: if (builtin.mode == .Debug) vk.DebugUtilsMessengerEXT else void,

pub fn init(
    allocator: std.mem.Allocator,
    vk_allocator: ?*const vk.AllocationCallbacks,
    window: anytype,
) !*const Context {
    const context = try allocator.create(Context);
    errdefer allocator.destroy(context);

    context.vk_allocator = vk_allocator;

    context.vkb = vk.BaseWrapper.load(struct {
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

    context.instance = utils.instance.createInstance(
        &context.vkb,
        allocator,
        vk_allocator,
    );

    context.vki = vk.InstanceWrapper.load(
        context.instance,
        context.vkb.dispatch.vkGetInstanceProcAddr.?,
    );

    errdefer context.vki.destroyInstance(context.instance);

    if (builtin.mode == .Debug) {
        context.debug_messanger =
            try utils.debug.debugMessenger(
                &context.vki,
                context.instance,
                vk_allocator,
            );
    }

    context.surface = try utils.win_surface.createWindowSurface(
        &context.vki,
        context.instance,
        window,
        vk_allocator,
    );

    return context;
}

pub fn deinit(self: *Context, allocator: std.mem.Allocator) void {
    allocator.destroy(self);
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const utils = @import("init/root.zig");

const QueueFamilies = opaque {};

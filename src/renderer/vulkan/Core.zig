const Core = @This();

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");
const os_tag = builtin.os.tag;

const Allocator = std.mem.Allocator;

const helpers = @import("helpers/root.zig");
const QueueFamilyIndices = helpers.physical_device.QueueFamilyIndices;
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");

const Dispatch = struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,
};

dispatch: *const Dispatch,

instance: vk.Instance,
physical_device: vk.PhysicalDevice,
device: vk.Device,

surface: vk.SurfaceKHR,

graphics_queue: vk.Queue,
graphics_family_index: u32,

present_queue: vk.Queue,
present_family_index: u32,

vk_mem: *VkAllocatorAdapter,

pub const log = std.log.scoped(.Renderer);

const vk_lib_path: [*:0]const u8 = switch (os_tag) {
    .windows => "C:\\Windows\\System32\\vulkan-1.dll",
    .linux => "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
    else => {},
};

var vk_lib: std.DynLib = undefined;

pub fn init(allocator: Allocator, window: anytype) !Core {
    vk_lib = try std.DynLib.openZ(vk_lib_path);

    const dispatch = try allocator.create(Dispatch);
    dispatch.vkb = .load(baseGetInstanceProcAddress);

    const vk_mem = try allocator.create(VkAllocatorAdapter);
    vk_mem.initInPlace(allocator);

    const alloc_callbacks = vk_mem.vkAllocatorCallbacks();

    const instance =
        try helpers.instance.createInstance(
            &dispatch.vkb,
            allocator,
            &alloc_callbacks,
        );

    const vkGetInstanceProcAddr =
        dispatch.vkb.dispatch.vkGetInstanceProcAddr.?;

    dispatch.vki = .load(instance, vkGetInstanceProcAddr);

    const surface =
        try helpers.win_surface.createWindowSurface(
            &dispatch.vki,
            instance,
            window,
            &alloc_callbacks,
        );

    var physical_devices: []vk.PhysicalDevice = &.{};
    var queue_family_indcies: []QueueFamilyIndices = &.{};

    try helpers.physical_device.pickPhysicalDevicesAlloc(
        &dispatch.vki,
        instance,
        surface,
        allocator,
        &physical_devices,
        &queue_family_indcies,
    );

    defer {
        allocator.free(queue_family_indcies);
        allocator.free(physical_devices);
    }

    var device: vk.Device = .null_handle;
    var physical_device: vk.PhysicalDevice = .null_handle;
    var queue_families: QueueFamilyIndices = undefined;

    for (physical_devices, queue_family_indcies, 0..) |p, q, i| {
        device = helpers.device
            .createDevice(&dispatch.vki, p, q, &alloc_callbacks) catch continue;
        physical_device = p;
        queue_families = q;
        log.debug("using GPU{}", .{i});
        break;
    }

    if (device == .null_handle)
        return error.DeviceCreationFailed;

    const vkGetDeviceProcAddr =
        dispatch.vki.dispatch.vkGetDeviceProcAddr.?;
    dispatch.vkd = .load(device, vkGetDeviceProcAddr);

    const graphics_queue = dispatch.vkd.getDeviceQueue(
        device,
        0,
        queue_families.graphics_family,
    );

    const present_queue = dispatch.vkd.getDeviceQueue(
        device,
        0,
        queue_families.present_family,
    );

    return .{
        .dispatch = dispatch,
        .instance = instance,
        .physical_device = physical_device,
        .device = device,
        .surface = surface,

        .graphics_queue = graphics_queue,
        .graphics_family_index = queue_families.graphics_family,

        .present_queue = present_queue,
        .present_family_index = queue_families.present_family,

        .vk_mem = vk_mem,
    };
}

pub fn deinit(self: *Core) void {
    const allocator = self.vk_mem.allocator;

    const alloc_callbacks = self.vk_mem.vkAllocatorCallbacks();

    self.dispatch
        .vkd.destroyDevice(self.device, &alloc_callbacks);

    self.dispatch
        .vki.destroySurfaceKHR(
        self.instance,
        self.surface,
        &alloc_callbacks,
    );

    self.dispatch
        .vki.destroyInstance(self.instance, &alloc_callbacks);

    allocator.destroy(self.dispatch);

    self.vk_mem.deinit();

    allocator.destroy(self.vk_mem);
}

fn baseGetInstanceProcAddress(
    _: vk.Instance,
    procname: [*:0]const u8,
) vk.PfnVoidFunction {
    return @ptrCast(
        vk_lib.lookup(*anyopaque, std.mem.span(procname)),
    );
}

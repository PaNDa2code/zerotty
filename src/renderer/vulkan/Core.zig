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

pub fn init(allocator: Allocator, window: anytype) !Core {
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

fn baseGetInstanceProcAddress(_: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
    const vk_lib_name = if (os_tag == .windows) "vulkan-1.dll" else "libvulkan.so.1";
    var vk_lib = std.DynLib.open(vk_lib_name) catch return null;
    return @ptrCast(vk_lib.lookup(*anyopaque, std.mem.span(procname)));
}


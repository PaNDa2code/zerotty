const Device = @This();

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice,
    properties: vk.PhysicalDeviceProperties,
    memory_properties: vk.PhysicalDeviceMemoryProperties,

    support_present: bool,

    graphic_family_index: u32,
    present_family_index: u32,
};

handle: vk.Device,
physical_device: PhysicalDevice,

vkd: vk.DeviceWrapper,
vk_allocator: ?*const vk.AllocationCallbacks,

pub const InitError = std.mem.Allocator.Error ||
    vk.InstanceWrapper.CreateDeviceError ||
    vk.InstanceWrapper.EnumeratePhysicalDevicesError ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfaceSupportKHRError ||
    error{NoSupportedGPU};

pub fn init(
    allocator: std.mem.Allocator,
    instance: *const Instance,
    surface: vk.SurfaceKHR, // optional
    required_extensions: []const [*:0]const u8,
) InitError!Device {
    const physical_devices = try getPhysicalDevices(allocator, instance, surface);
    defer allocator.free(physical_devices);

    for (physical_devices) |physical_device| {
        if (surface != .null_handle and !physical_device.support_present)
            continue;

        const device = createDevice(instance, physical_device, required_extensions) catch |err|
            switch (err) {
                error.OutOfHostMemory, error.ExtensionNotPresent => continue,
                else => return err,
            };

        const vkGetDeviceProcAddr = instance.vki.dispatch.vkGetDeviceProcAddr.?;
        const vkd = vk.DeviceWrapper.load(device, vkGetDeviceProcAddr);

        return .{
            .handle = device,
            .physical_device = physical_device,

            .vkd = vkd,
            .vk_allocator = instance.vk_allocator,
        };
    }

    return error.NoSupportedGPU;
}

pub fn deinit(self: *const Device) void {
    self.vkd.destroyDevice(self.handle, self.vk_allocator);
}

pub const WaitIdleError = vk.DeviceWrapper.DeviceWaitIdleError;

pub fn waitIdle(self: *const Device) WaitIdleError!void {
    try self.vkd.deviceWaitIdle(self.handle);
}

pub const CreateFenceError = vk.DeviceWrapper.CreateFenceError;

pub fn createFence(self: *const Device) CreateFenceError!vk.Fence {
    return self.vkd.createFence(
        self.handle,
        &.{},
        self.vk_allocator,
    );
}

pub const CreateSemaphoreError = vk.DeviceWrapper.CreateSemaphoreError;

pub fn createSemaphore(self: *const Device) CreateSemaphoreError!vk.Semaphore {
    return self.vkd.createSemaphore(
        self.handle,
        &.{},
        self.vk_allocator,
    );
}

fn createDevice(
    instance: *const Instance,
    physical_device: PhysicalDevice,
    required_extensions: []const [*:0]const u8,
) !vk.Device {
    const graphic_family_index = physical_device.graphic_family_index;
    const present_family_index = physical_device.present_family_index;

    var queue_infos: [2]vk.DeviceQueueCreateInfo = undefined;
    var queue_count: usize = 0;

    queue_infos[queue_count] = .{
        .queue_family_index = graphic_family_index,
        .queue_count = 1,
        .p_queue_priorities = &.{1.0},
    };
    queue_count += 1;

    if (physical_device.support_present and
        present_family_index != graphic_family_index)
    {
        queue_infos[queue_count] = .{
            .queue_family_index = present_family_index,
            .queue_count = 1,
            .p_queue_priorities = &.{1.0},
        };
        queue_count += 1;
    }

    const layers =
        if (builtin.mode == .Debug)
            [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"}
        else
            [_][*:0]const u8{};

    const sync2_features = vk.PhysicalDeviceSynchronization2Features{
        .synchronization_2 = .true,
    };

    const device_features = vk.PhysicalDeviceFeatures{};

    const device_create_info = vk.DeviceCreateInfo{
        .p_next = @ptrCast(&sync2_features),

        .queue_create_info_count = @intCast(queue_count),
        .p_queue_create_infos = &queue_infos,

        .enabled_extension_count = @intCast(required_extensions.len),
        .pp_enabled_extension_names = required_extensions.ptr,

        .enabled_layer_count = layers.len,
        .pp_enabled_layer_names = &layers,

        .p_enabled_features = &device_features,
    };

    return instance.vki.createDevice(
        physical_device.handle,
        &device_create_info,
        instance.vk_allocator,
    );
}

inline fn getPhysicalDevices(
    allocator: std.mem.Allocator,
    instance: *const Instance,
    surface: vk.SurfaceKHR,
) ![]PhysicalDevice {
    const handles = try instance.vki
        .enumeratePhysicalDevicesAlloc(instance.handle, allocator);

    defer allocator.free(handles);

    var physical_devices = try allocator.alloc(PhysicalDevice, handles.len);

    for (handles, 0..) |handle, i| {
        physical_devices[i].support_present = false;

        queryPhysicalDeviceInfo(instance, handle, &physical_devices[i]);
        try selectQueueFamilies(allocator, instance, handle, surface, &physical_devices[i]);
    }

    return physical_devices;
}

fn queryPhysicalDeviceInfo(
    instance: *const Instance,
    handle: vk.PhysicalDevice,
    out: *PhysicalDevice,
) void {
    out.handle = handle;

    out.properties =
        instance.vki.getPhysicalDeviceProperties(handle);
    // out.features =
    //     instance.vki.getPhysicalDeviceFeatures(handle);
    out.memory_properties =
        instance.vki.getPhysicalDeviceMemoryProperties(handle);
}

fn selectQueueFamilies(
    allocator: std.mem.Allocator,
    instance: *const Instance,
    handle: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    out: *PhysicalDevice,
) !void {
    const queue_props = try instance.vki
        .getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, allocator);
    defer allocator.free(queue_props);

    var graphics: ?u32 = null;
    var present: ?u32 = null;
    var graphics_present: ?u32 = null;

    for (queue_props, 0..) |props, j| {
        const idx: u32 = @intCast(j);

        const graphics_support = props.queue_flags.graphics_bit;

        const present_support = surface != .null_handle and
            try instance.vki.getPhysicalDeviceSurfaceSupportKHR(
                handle,
                idx,
                surface,
            ) == .true;

        if (graphics_support and graphics == null)
            graphics = idx;

        if (present_support and present == null)
            present = idx;

        if (graphics_support and present_support) {
            graphics_present = idx;
            break;
        }
    }

    if (graphics_present) |i| {
        out.graphic_family_index = i;
        out.present_family_index = i;
        out.support_present = true;
        return;
    }

    if (present) |i| {
        out.present_family_index = i;
        out.support_present = true;
    }

    if (graphics) |i| {
        out.graphic_family_index = i;
    }
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const Instance = @import("Instance.zig");

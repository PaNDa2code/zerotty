const RenderContext = @This();

instance: *const core.Instance,
device: *const core.Device,

surface: vk.SurfaceKHR,

queue: core.Queue,

// allocator: std.mem.Allocator,
allocator_adapter: *core.memory.AllocatorAdapter,
device_allocator: *core.memory.DeviceAllocator,

pub fn init(allocator: std.mem.Allocator, window_handles: window.WindowHandles) !RenderContext {
    const allocator_adapter = try core.memory.AllocatorAdapter.init(allocator);

    const surface_creation_info = SurfaceCreationInfo.fromWindowHandles(window_handles);

    var arina = std.heap.ArenaAllocator.init(allocator);
    defer arina.deinit();

    const instance_extensions = try surface_creation_info.instanceExtensionsAlloc(arina.allocator());

    const instance = try allocator.create(core.Instance);
    instance.* = try core.Instance.init(
        allocator,
        &allocator_adapter.alloc_callbacks,
        instance_extensions,
    );
    errdefer instance.deinit();

    const surface = try createWindowSurface(instance, surface_creation_info);

    const device = try allocator.create(core.Device);
    device.* = try .init(
        allocator,
        instance,
        surface,
        SurfaceCreationInfo.deviceExtensions(),
    );
    errdefer device.deinit();

    const device_allocator = try allocator.create(core.memory.DeviceAllocator);

    device_allocator.* = .init(device, allocator);

    const queue = core.Queue.init(
        device,
        device.physical_device.graphic_family_index,
        0,
        true,
    );

    return .{
        .instance = instance,
        .device = device,

        .surface = surface,

        .queue = queue,

        .allocator_adapter = allocator_adapter,
        .device_allocator = device_allocator,
    };
}

pub fn deinit(self: *RenderContext) void {
    const allocator = self.allocator_adapter.allocator;

    self.device.deinit();
    self.instance.deinit();

    self.allocator_adapter.deinit();

    allocator.destroy(self.instance);
    allocator.destroy(self.device);
    allocator.destroy(self.device_allocator);
}

const std = @import("std");
const vk = @import("vulkan");

const core = @import("../core/root.zig");

const window = @import("window");
const window_surface = @import("window_surface.zig");
const SurfaceCreationInfo = window_surface.SurfaceCreationInfo;
const createWindowSurface = window_surface.createWindowSurface;

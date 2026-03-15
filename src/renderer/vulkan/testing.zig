const std = @import("std");
const core = @import("core/root.zig");

var mutex: std.Thread.Mutex = .{};

const allocator = std.heap.c_allocator;
var vk_alloc: ?*core.memory.AllocatorAdapter = null;
var instance: ?core.Instance = null;
var device: ?core.Device = null;

fn allocAdapter() *core.memory.AllocatorAdapter {
    if (vk_alloc) |ptr| return ptr;
    vk_alloc = core.memory.AllocatorAdapter.init(allocator) catch @panic("OOM");
    return vk_alloc.?;
}

pub fn getTestInstance() !*const core.Instance {
    if (instance) |*ptr| return ptr;

    instance = try core.Instance.init(
        std.testing.allocator,
        &allocAdapter().alloc_callbacks,
        &.{},
    );

    return &(instance.?);
}

pub fn getTestDevice() !*const core.Device {
    if (device) |*ptr| return ptr;

    device = try core.Device.init(
        std.testing.allocator,
        try getTestInstance(),
        .null_handle,
        &.{},
    );

    return &(device.?);
}

pub fn getTestDeviceLocked() !*const core.Device {
    mutex.lock();
    return getTestDevice();
}

pub fn unlockTestDevice() void {
    mutex.unlock();
}

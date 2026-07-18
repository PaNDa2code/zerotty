const std = @import("std");
const core = @import("core/root.zig");

var mutex: std.atomic.Mutex = .unlocked;

const allocator = std.testing.allocator;

var vk_alloc: ?*core.memory.AllocatorAdapter = null;
var instance: ?core.Instance = null;
var device: ?core.Device = null;

fn allocAdapter() *core.memory.AllocatorAdapter {
    if (vk_alloc) |ptr| return ptr;
    vk_alloc = core.memory.AllocatorAdapter.init(allocator) catch @panic("OOM");
    return vk_alloc.?;
}

pub fn getTestInstance() *const core.Instance {
    if (instance) |*ptr| return ptr;

    instance = core.Instance.init(
        std.testing.allocator,
        &allocAdapter().alloc_callbacks,
        &.{},
    ) catch |err| {
        std.debug.panic("testing Instance creation failed: {}", .{err});
    };

    return &(instance.?);
}

pub fn getTestDevice() *const core.Device {
    if (device) |*ptr| return ptr;

    device = core.Device.init(
        std.testing.allocator,
        getTestInstance(),
        .null_handle,
        &.{},
    ) catch |err| {
        std.debug.panic("testing Device creation failed: {}", .{err});
    };

    return &(device.?);
}

pub fn getTestDeviceLocked() *const core.Device {
    while (!mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    return getTestDevice();
}

pub fn unlockTestDevice() void {
    mutex.unlock();
}

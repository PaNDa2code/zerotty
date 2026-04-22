const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");

pub const BufferHandle = enum(u32) { invalid = std.math.maxInt(u32), _ };
pub const MemoryHandle = enum(u32) { invalid = std.math.maxInt(u32), _ };

pub const BufferView = struct {
    handle: BufferHandle,
    registry: *BufferRegistry,
};

pub const BufferRegistry = struct {
    device: *const core.Device,
    device_allocator: *const core.memory.DeviceAllocator,
    allocator: std.mem.Allocator,

    buffer_map: std.AutoHashMapUnmanaged(BufferHandle, vk.Buffer) = .empty,

    // pub fn init(
    //     device: *const core.Device,
    //     device_allocator: *const core.memory.DeviceAllocator,
    //     allocator: std.mem.Allocator,
    // ) !BufferRegistry {
    //     return .{
    //         .device = device,
    //         .device_allocator = device_allocator,
    //         .allocator = allocator,
    //     };
    // }
    //
    // pub fn createBuffer(
    //     self: *BufferRegistry,
    //     size: usize,
    //     usage: vk.BufferUsageFlags,
    //     mem_props: vk.MemoryPropertyFlags,
    //     sharing: vk.SharingMode,
    // ) core.Buffer {}
    //
    // pub fn deinit(self: *BufferRegistry) void {}
};

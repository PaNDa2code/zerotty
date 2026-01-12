const Buffer = @This();

device: *const Device,

handle: vk.Buffer,
usage: vk.BufferUsageFlags,
mem_requirements: vk.MemoryRequirements,

mem_alloc: ?DeviceAllocation = null,

pub const InitError = vk.DeviceWrapper.CreateBufferError;

pub fn init(
    device: *const Device,
    size: usize,
    usage: vk.BufferUsageFlags,
    sharing: vk.SharingMode,
) InitError!Buffer {
    const buffer_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = sharing,
    };

    const handle = try device.vkd.createBuffer(
        device.handle,
        &buffer_info,
        device.vk_allocator,
    );

    const mem_requirements = device.vkd.getBufferMemoryRequirements(device.handle, handle);

    return .{
        .handle = handle,
        .usage = usage,
        .mem_requirements = mem_requirements,
    };
}

pub fn deinit(self: *const Buffer) void {
    self.device.vkd.destroyBuffer(
        self.device.handle,
        self.handle,
        self.device.vk_allocator,
    );
}

pub const BindMemoryError = vk.DeviceWrapper.BindBufferMemoryError;

pub fn bindMemory(
    self: *const Buffer,
    allocation: DeviceAllocation,
) BindMemoryError!void {
    try self.device.vkd.bindBufferMemory(
        self.device.handle,
        self.handle,
        allocation.memory,
        allocation.offset,
    );

    self.mem_alloc = allocation;
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const Device = @import("Device.zig");
const DeviceAllocator = @import("../memory/DeviceAllocator.zig");
const DeviceAllocation = DeviceAllocator.DeviceAllocation;

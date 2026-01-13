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
        .device = device,
        .handle = handle,
        .usage = usage,
        .mem_requirements = mem_requirements,
    };
}

pub const InitAllocError = InitError || BindMemoryError ||
    DeviceAllocator.AllocError;

pub fn initAlloc(
    device_allocator: *DeviceAllocator,
    size: usize,
    usage: vk.BufferUsageFlags,
    mem_props: vk.MemoryPropertyFlags,
    sharing: vk.SharingMode,
) InitAllocError!Buffer {
    var buffer = try init(device_allocator.device, size, usage, sharing);

    const allocation = try device_allocator.alloc(
        buffer.mem_requirements.size,
        buffer.mem_requirements.memory_type_bits,
        mem_props,
    );

    try buffer.bindMemory(allocation);

    return buffer;
}

pub fn deinit(self: *const Buffer, device_allocator: ?*DeviceAllocator) void {
    if (device_allocator)|allocator| {
        if (self.mem_alloc) |alloc| {
            allocator.free(alloc);
        }
    }

    self.device.vkd.destroyBuffer(
        self.device.handle,
        self.handle,
        self.device.vk_allocator,
    );
}

pub const BindMemoryError = vk.DeviceWrapper.BindBufferMemoryError;

pub fn bindMemory(
    self: *Buffer,
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

pub fn getDescriptorBufferInfo(self: *const Buffer) vk.DescriptorBufferInfo {
    return .{
        .buffer = self.handle,
        .offset = 0,
        .range = self.mem_requirements.size,
    };
}

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const Device = @import("Device.zig");
const DeviceAllocator = @import("../memory/DeviceAllocator.zig");
const DeviceAllocation = DeviceAllocator.DeviceAllocation;

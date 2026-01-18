const DeviceAllocator = @This();

pub const DeviceAllocation = struct {
    memory: vk.DeviceMemory,
    size: usize,
    offset: usize,

    memory_type_index: u32,
    props: vk.MemoryPropertyFlags,

    host_address: usize = 0,

    pub fn map(self: *DeviceAllocation, device: *const core.Device) usize {
        if (!self.props.host_visible_bit)
            return 0;

        if (self.host_address != 0)
            return @ptrFromInt(self.host_address);

        self.host_address = @intFromPtr(device.vkd.mapMemory(
            device.handle,
            self.memory,
            self.offset,
            self.size,
            self.props,
        ) catch null);

        return self.host_address;
    }
    pub fn hostPtr(self: *DeviceAllocation, T: type, device: *const core.Device) ?*T {
        return @ptrFromInt(self.map(device));
    }
};

device: *const core.Device,
std_allocator: std.mem.Allocator,

pub fn init(device: *const core.Device, std_allocator: std.mem.Allocator) DeviceAllocator {
    return .{
        .device = device,
        .std_allocator = std_allocator,
    };
}

pub const AllocError = error{
    NoSuitableMemoryType,
} || vk.DeviceWrapper.AllocateMemoryError;

pub fn alloc(
    self: *DeviceAllocator,
    size: usize,
    type_bits: u32,
    flags: vk.MemoryPropertyFlags,
) AllocError!DeviceAllocation {
    const memory_type_index = try findMemoryType(
        &self.device.physical_device.memory_properties,
        type_bits,
        flags,
    );

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = size,
        .memory_type_index = memory_type_index,
    };

    const memory = try self.device.vkd.allocateMemory(
        self.device.handle,
        &alloc_info,
        self.device.vk_allocator,
    );

    return .{
        .memory = memory,
        .size = size,
        .offset = 0,
        .memory_type_index = memory_type_index,
        .props = self.device.physical_device
            .memory_properties
            .memory_types[memory_type_index]
            .property_flags,
    };
}

/// returns `true` if memory resized in place
pub fn resize(self: *DeviceAllocator, allocation: *DeviceAllocation, new_size: usize) bool {
    if (allocation.size >= new_size)
        return true;

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = new_size,
        .memory_type_index = allocation.memory_type_index,
    };

    const memory = try self.device.vkd.allocateMemory(
        self.device.handle,
        &alloc_info,
        self.device.vk_allocator,
    );

    self.device.vkd.freeMemory(
        self.device,
        allocation.memory,
        self.device.vk_allocator,
    );

    allocation.memory = memory;
    allocation.offset = 0;
    allocation.size = new_size;

    return false;
}

pub fn free(self: *DeviceAllocator, allocation: DeviceAllocation) void {
    self.device.vkd.freeMemory(
        self.device.handle,
        allocation.memory,
        self.device.vk_allocator,
    );
}

fn findMemoryType(
    mem_properties: *const vk.PhysicalDeviceMemoryProperties,
    memory_type_bits: u32,
    properties: vk.MemoryPropertyFlags,
) !u32 {
    var mask = memory_type_bits;
    while (mask != 0) : (mask &= mask - 1) {
        const i = @ctz(mask);
        if (i < mem_properties.memory_type_count and
            mem_properties.memory_types[i].property_flags.contains(properties))
        {
            return i;
        }
    }
    return error.NoSuitableMemoryType;
}

const std = @import("std");
const vk = @import("vulkan");
const AllocatorAdapter = @import("AllocatorAdapter.zig");
const core = @import("../core/root.zig");

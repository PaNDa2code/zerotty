const VkDeviceAlloator = @This();

const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;
const Core = @import("Core.zig");

pub const Allocation = struct {
    memory: vk.DeviceMemory,
    size: usize,
    offset: usize,

    property_flags: vk.MemoryPropertyFlags,
    mem_type_index: u32,
    host_address: usize = 0,

    pub fn map(self: *Allocation, core: *const Core) !void {
        if (self.host_address != 0) return;
        const ptr = try core.vkd().mapMemory(
            core.device,
            self.memory,
            self.offset,
            self.size,
            .{},
        );
        self.host_address = @intFromPtr(ptr);
    }

    pub fn unmap(self: *Allocation, core: *const Core) !void {
        if (self.host_address == 0) return;
        core.vkd().unmapMemory(
            core.device,
            self.memory,
        );
        self.host_address = 0;
    }

    pub fn hostPtr(self: *Allocation, T: type) ?*T {
        return @ptrFromInt(self.host_address);
    }

    pub fn hostSlicePtr(self: *Allocation, T: type) ?[*]T {
        return @ptrFromInt(self.host_address);
    }

    pub fn hostVisable(self: *Allocation) bool {
        return self.property_flags.host_visible_bit;
    }
};

allocator: Allocator,
mem_properties: vk.PhysicalDeviceMemoryProperties,

pub fn init(
    core: *const Core,
    allocator: Allocator,
) !VkDeviceAlloator {
    const mem_properties =
        core.vki().getPhysicalDeviceMemoryProperties(core.physical_device);

    return .{
        .allocator = allocator,
        .mem_properties = mem_properties,
    };
}

pub fn alloc(
    self: *VkDeviceAlloator,
    core: *const Core,
    size: usize,
    type_bits: u32,
    flags: vk.MemoryPropertyFlags,
) !Allocation {
    const memory_type_index =
        try findMemoryType(&self.mem_properties, type_bits, flags);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = size,
        .memory_type_index = memory_type_index,
    };

    const mem =
        try core.vkd().allocateMemory(
            core.device,
            &alloc_info,
            &core.vk_mem.alloc_callbacks,
        );

    return .{
        .memory = mem,
        .size = size,
        .offset = 0,
        .property_flags = self
            .mem_properties
            .memory_types[memory_type_index]
            .property_flags,

        .mem_type_index = memory_type_index,
    };
}

const ResizeResult = enum { inplace, reallocated };

pub fn resize(
    self: *VkDeviceAlloator,
    core: *const Core,
    allocation: *Allocation,
    new_size: usize,
) !ResizeResult {
    _ = self;

    if (new_size <= allocation.size) return .inplace;

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = new_size,
        .memory_type_index = allocation.mem_type_index,
    };

    const mem =
        try core.vkd().allocateMemory(
            core.device,
            &alloc_info,
            &core.vk_mem.alloc_callbacks,
        );

    allocation.size = new_size;
    allocation.memory = mem;

    return .reallocated;
}

pub fn free(
    _: *VkDeviceAlloator,
    core: *const Core,
    allocation: Allocation,
) void {
    core.vkd().freeMemory(
        core.device,
        allocation.memory,
        &core.vk_mem.vkAllocatorCallbacks(),
    );
}

pub fn findMemoryType(
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

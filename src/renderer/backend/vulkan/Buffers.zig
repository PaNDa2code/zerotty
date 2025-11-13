const Buffers = @This();

const std = @import("std");
const vk = @import("vulkan");

const Atlas = @import("../../../font/Atlas.zig");
const Grid = @import("../../common/Grid.zig");
const Cell = Grid.Cell;

const Core = @import("Core.zig");
const math = @import("../../common/math.zig");
const Vec4 = math.Vec4;

pub const BufferResource = struct {
    handle: vk.Buffer,
    memory: vk.DeviceMemory,
    size: usize,
};

vertex_buffer: BufferResource,
staging_buffer: BufferResource,
uniform_buffer: BufferResource,

pub fn init(core: *const Core, options: anytype) !Buffers {
    const vki = &core.dispatch.vki;
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(core.physical_device);

    var vertex_buffer: vk.Buffer = .null_handle;
    var vertex_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        core.device,
        &mem_properties,
        options.vertex_size,
        .{
            .vertex_buffer_bit = true,
            .transfer_dst_bit = true,
        },
        .{},
        &vertex_buffer,
        &vertex_memory,
        &alloc_callbacks,
    );

    var uniform_buffer: vk.Buffer = .null_handle;
    var uniform_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        core.device,
        &mem_properties,
        @sizeOf(UniformsBlock),
        .{ .uniform_buffer_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        &uniform_buffer,
        &uniform_memory,
        &alloc_callbacks,
    );

    var vertex_staging_buffer: vk.Buffer = .null_handle;
    var vertex_staging_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        core.device,
        &mem_properties,
        options.staging_size,
        .{ .transfer_src_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        &vertex_staging_buffer,
        &vertex_staging_memory,
        &alloc_callbacks,
    );

    return .{
        .vertex_buffer = .{
            .handle = vertex_buffer,
            .memory = vertex_memory,
            .size = options.vertex_size,
        },
        .staging_buffer = .{
            .handle = vertex_staging_buffer,
            .memory = vertex_staging_memory,
            .size = options.staging_size,
        },
        .uniform_buffer = .{
            .handle = uniform_buffer,
            .memory = uniform_memory,
            .size = options.uniform_size,
        },
    };
}

pub fn deinit(self: *const Buffers, core: *const Core) void {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    vkd.destroyBuffer(core.device, self.vertex_buffer.handle, &alloc_callbacks);
    vkd.destroyBuffer(core.device, self.staging_buffer.handle, &alloc_callbacks);
    vkd.destroyBuffer(core.device, self.uniform_buffer.handle, &alloc_callbacks);

    vkd.freeMemory(core.device, self.vertex_buffer.memory, &alloc_callbacks);
    vkd.freeMemory(core.device, self.staging_buffer.memory, &alloc_callbacks);
    vkd.freeMemory(core.device, self.uniform_buffer.memory, &alloc_callbacks);
}

pub fn stageVertexData(
    self: *const Buffers,
    core: *const Core,
    grid: *const Grid,
) !void {
    const vkd = &core.dispatch.vkd;

    const staging_ptr =
        try vkd.mapMemory(
            core.device,
            self.staging_buffer.memory,
            0,
            1024 * 16,
            .{},
        );

    defer vkd.unmapMemory(core.device, self.staging_buffer.memory);

    const slice = @as([*]Cell, @ptrFromInt(@intFromPtr(staging_ptr)))[0..128];
    @memset(slice, std.mem.zeroes(Cell));

    const n = @min(slice.len, grid.data().len);
    @memcpy(slice[0..n], grid.data()[0..n]);
}

pub fn createBuffer(
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    physical_mem_props: *const vk.PhysicalDeviceMemoryProperties,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    mem_props: vk.MemoryPropertyFlags,
    p_buffer: *vk.Buffer,
    p_device_memory: *vk.DeviceMemory,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !void {
    const buffer_create_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };
    const buffer = try vkd.createBuffer(device, &buffer_create_info, vk_mem_cb);

    const mem_reqs = vkd.getBufferMemoryRequirements(device, buffer);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = findMemoryType(physical_mem_props, mem_reqs.memory_type_bits, mem_props),
    };

    const memory = try vkd.allocateMemory(device, &alloc_info, vk_mem_cb);

    try vkd.bindBufferMemory(device, buffer, memory, 0);

    p_buffer.* = buffer;
    p_device_memory.* = memory;
}

pub fn findMemoryType(
    mem_properties: *const vk.PhysicalDeviceMemoryProperties,
    type_filter: u32,
    properties: vk.MemoryPropertyFlags,
) u32 {
    for (0..mem_properties.memory_type_count) |i| {
        if ((type_filter & (std.math.shl(u32, 1, i))) != 0 and
            mem_properties.memory_types[i].property_flags.contains(properties))
        {
            return @intCast(i);
        }
    }
    std.debug.panic("Failed to find suitable memory index for type {f}!", .{properties});
}

pub const UniformsBlock = packed struct {
    cell_height: f32,
    cell_width: f32,
    screen_height: f32,
    screen_width: f32,
    atlas_cols: f32,
    atlas_rows: f32,
    atlas_width: f32,
    atlas_height: f32,
    descender: f32,
};

pub var uniform_buffer_ptr: ?*UniformsBlock = null;
/// set ubo values
pub fn updateUniformData(
    self: *const Buffers,
    core: *const Core,
    data: *const UniformsBlock,
) !void {
    const vkd = &core.dispatch.vkd;

    const ptr = try vkd.mapMemory(
        core.device,
        self.uniform_buffer.memory,
        0,
        @sizeOf(UniformsBlock),
        .{},
    );
    // defer vkd.unmapMemory(core.device, self.uniform_buffer.memory);

    @as(*UniformsBlock, @ptrCast(@alignCast(ptr))).* = data.*;
    uniform_buffer_ptr = @ptrCast(@alignCast(ptr));
}

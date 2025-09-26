const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createBuffers(self: *VulkanRenderer, vertex_size: usize) !void {
    const vkd = self.device_wrapper;
    const vki = self.instance_wrapper;
    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(self.physical_device);

    var vertex_buffer: vk.Buffer = .null_handle;
    var vertex_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        self.device,
        &mem_properties,
        vertex_size,
        .{
            .vertex_buffer_bit = true,
            .transfer_dst_bit = true,
        },
        .{},
        &vertex_buffer,
        &vertex_memory,
        &mem_cb,
    );

    var uniform_buffer: vk.Buffer = .null_handle;
    var uniform_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        self.device,
        &mem_properties,
        @sizeOf(UniformsBlock),
        .{ .uniform_buffer_bit = true },
        .{},
        &uniform_buffer,
        &uniform_memory,
        &mem_cb,
    );

    var vertex_staging_buffer: vk.Buffer = .null_handle;
    var vertex_staging_memory: vk.DeviceMemory = .null_handle;

    try createBuffer(
        vkd,
        self.device,
        &mem_properties,
        vertex_size,
        .{ .transfer_src_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
        &vertex_staging_buffer,
        &vertex_staging_memory,
        &mem_cb,
    );

    self.vertex_buffer = vertex_buffer;
    self.vertex_memory = vertex_memory;

    self.uniform_buffer = uniform_buffer;
    self.uniform_memory = uniform_memory;

    self.staging_buffer = vertex_staging_buffer;
    self.staging_memory = vertex_staging_memory;
}

pub fn uploadVertexData(self: *const VulkanRenderer) !void {
    const full_quad = [_]Vec4(f32){
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 }, // Bottom-left
        .{ .x = 1.0, .y = 0.0, .z = 1.0, .w = 0.0 }, // Bottom-right
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // Top-right
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 }, // Top-right
        .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 }, // Top-left
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 }, // Bottom-left
    };

    const vkd = self.device_wrapper;
    const vertex_data_ptr = try vkd.mapMemory(self.device, self.staging_memory, 0, 128, .{});
    defer vkd.unmapMemory(self.device, self.staging_memory);

    @memcpy(@as([*]Vec4(f32), @ptrCast(@alignCast(vertex_data_ptr)))[0..6], full_quad[0..]);

    @memset(@as([*]Cell, @ptrCast(@alignCast(vertex_data_ptr)))[0..1], Cell{
        .row = 0,
        .col = 0,
        .char = 0,
        .fg_color = .White,
        .bg_color = .Black,
        .glyph_info = .{
            .coord_start = .zero,
            .coord_end = .zero,
            .bearing = .zero,
        },
    });
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

pub fn getVertexBindingDescriptions() []const vk.VertexInputBindingDescription {
    return &[_]vk.VertexInputBindingDescription{
        .{ .binding = 0, .stride = @sizeOf(Vec4(f32)), .input_rate = .vertex },
        .{ .binding = 1, .stride = @sizeOf(Cell), .input_rate = .instance },
    };
}

pub fn getVertexAttributeDescriptions() []const vk.VertexInputAttributeDescription {
    const descriptions = [_]vk.VertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = .r32g32b32a32_sfloat, .offset = 0 },
        .{ .location = 1, .binding = 1, .format = .r32_uint, .offset = @offsetOf(Cell, "row") },
        .{ .location = 2, .binding = 1, .format = .r32_uint, .offset = @offsetOf(Cell, "col") },
        .{ .location = 3, .binding = 1, .format = .r32_uint, .offset = @offsetOf(Cell, "char") },
        .{ .location = 4, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = @offsetOf(Cell, "fg_color") },
        .{ .location = 5, .binding = 1, .format = .r32g32b32a32_sfloat, .offset = @offsetOf(Cell, "bg_color") },
        .{
            .location = 6,
            .binding = 1,
            .format = .r32g32_uint,
            .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_start"),
        },
        .{
            .location = 7,
            .binding = 1,
            .format = .r32g32_uint,
            .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_end"),
        },
        .{
            .location = 8,
            .binding = 1,
            .format = .r32g32_sint,
            .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "bearing"),
        },
    };

    return descriptions[0..];
}

inline fn findMemoryType(
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

const Atlas = @import("../../font/Atlas.zig");
const Cell = @import("../Grid.zig").Cell;

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

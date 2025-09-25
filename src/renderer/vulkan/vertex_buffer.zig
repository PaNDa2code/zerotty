const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createVertexBuffer(self: *VulkanRenderer, vertex_size: usize, uniform_size: usize) !void {
    const vkd = self.device_wrapper;
    const vki = self.instance_wrapper;
    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(self.physical_device);

    const vertex_buffer = blk: {
        const buffer_create_info = vk.BufferCreateInfo{
            .size = vertex_size,
            .usage = .{ .vertex_buffer_bit = true },
            .sharing_mode = .exclusive,
        };
        const buffer = try vkd.createBuffer(self.device, &buffer_create_info, &mem_cb);

        const mem_reqs = vkd.getBufferMemoryRequirements(self.device, buffer);

        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = mem_reqs.size,
            .memory_type_index = findMemoryType(&mem_properties, mem_reqs.memory_type_bits, .{}),
        };

        const vertex_buffer_memory = try vkd.allocateMemory(self.device, &alloc_info, &mem_cb);

        try vkd.bindBufferMemory(self.device, buffer, vertex_buffer_memory, 0);

        break :blk buffer;
    };

    const uniform_buffer = blk: {
        const buffer_create_info = vk.BufferCreateInfo{
            .size = uniform_size,
            .usage = .{ .uniform_buffer_bit = true },
            .sharing_mode = .exclusive,
        };
        const buffer = try vkd.createBuffer(self.device, &buffer_create_info, &mem_cb);

        const mem_reqs = vkd.getBufferMemoryRequirements(self.device, buffer);

        const alloc_info = vk.MemoryAllocateInfo{
            .allocation_size = mem_reqs.size,
            .memory_type_index = findMemoryType(&mem_properties, mem_reqs.memory_type_bits, .{}),
        };

        const vertex_buffer_memory = try vkd.allocateMemory(self.device, &alloc_info, &mem_cb);

        try vkd.bindBufferMemory(self.device, buffer, vertex_buffer_memory, 0);

        break :blk buffer;
    };

    self.vertex_buffer = vertex_buffer;
    self.uniform_buffer = uniform_buffer;
}

pub fn createUniformBuffer(
    vki: *const vk.InstanceWrapper,
    vkd: *const vk.DeviceWrapper,
    dev: vk.Device,
    physical_device: vk.PhysicalDevice,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.Buffer {
    const buffer_info = vk.BufferCreateInfo{
        .size = @sizeOf(UniformsBlock),
        .usage = .{ .uniform_buffer_bit = true },
        .sharing_mode = .exclusive,
    };

    const buffer = try vkd.createBuffer(dev, &buffer_info, vkmemcb);

    const mem_req = vkd.getBufferMemoryRequirements(dev, buffer);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_req.size,
        .memory_type_index = findMemoryType(vki, physical_device, mem_req.memory_type_bits, .{}),
    };

    const buffer_memory = try vkd.allocateMemory(dev, &alloc_info, vkmemcb);

    try vkd.bindBufferMemory(dev, buffer, buffer_memory, 0);

    return buffer;
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
        .{ .location = 6, .binding = 1, .format = .r32g32_uint, .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_start") },
        .{ .location = 7, .binding = 1, .format = .r32g32_uint, .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "coord_end") },
        .{ .location = 8, .binding = 1, .format = .r32g32_sint, .offset = @offsetOf(Cell, "glyph_info") + @offsetOf(Atlas.GlyphInfo, "bearing") },
    };

    return descriptions[0..];
}

inline fn findMemoryType(
    mem_properties: *const vk.PhysicalDeviceMemoryProperties,
    typeFilter: u32,
    properties: vk.MemoryPropertyFlags,
) u32 {
    for (0..mem_properties.memory_type_count) |i| {
        if ((typeFilter & (std.math.shr(u32, 1, i))) != 0 and
            mem_properties.memory_types[i].property_flags.contains(properties))
        {
            return @intCast(i);
        }
    }
    @panic("Failed to find suitable memory type!");
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

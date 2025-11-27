const Buffers = @This();

const std = @import("std");
const vk = @import("vulkan");

const Atlas = @import("../../../font/Atlas.zig");
const Grid = @import("../../common/Grid.zig");
const Cell = Grid.Cell;

const Core = @import("Core.zig");
const DeviceAllocator = @import("VkDeviceAllocator.zig");

const math = @import("../../common/math.zig");
const Vec4 = math.Vec4;

pub const findMemoryType = DeviceAllocator.findMemoryType;

pub const BufferResource = struct {
    handle: vk.Buffer,
    memory: DeviceAllocator.Allocation,
};

vertex_buffer: BufferResource,
staging_buffer: BufferResource,
uniform_buffer: BufferResource,

glyph_ssbo: BufferResource,
style_ssbo: BufferResource,

device_allocator: DeviceAllocator,

pub fn init(core: *const Core, options: anytype) !Buffers {
    var device_allocator = try DeviceAllocator.init(
        core,
        core.vk_mem.allocator,
    );

    const vertex_res = try createBuffer(
        core,
        &device_allocator,
        options.vertex_size,
        .{
            .vertex_buffer_bit = true,
            .transfer_dst_bit = true,
        },
        .{},
    );

    const uniform_res = try createBuffer(
        core,
        &device_allocator,
        @sizeOf(UniformsBlock),
        .{ .uniform_buffer_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );

    const staging_res = try createBuffer(
        core,
        &device_allocator,
        options.staging_size,
        .{ .transfer_src_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );

    const glyph_ssbo = try createBuffer(
        core,
        &device_allocator,
        options.glyph_ssbo_size,
        .{ .storage_buffer_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );

    const style_ssbo = try createBuffer(
        core,
        &device_allocator,
        options.style_ssbo_size,
        .{ .storage_buffer_bit = true },
        .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        },
    );

    return .{
        .vertex_buffer = vertex_res,
        .staging_buffer = staging_res,
        .uniform_buffer = uniform_res,
        .glyph_ssbo = glyph_ssbo,
        .style_ssbo = style_ssbo,
        .device_allocator = device_allocator,
    };
}

pub fn deinit(self: *Buffers, core: *const Core) void {
    const vkd = &core.dispatch.vkd;
    const vk_cb = core.vk_mem.vkAllocatorCallbacks();

    // Destroy buffers
    vkd.destroyBuffer(core.device, self.vertex_buffer.handle, &vk_cb);
    vkd.destroyBuffer(core.device, self.staging_buffer.handle, &vk_cb);
    vkd.destroyBuffer(core.device, self.uniform_buffer.handle, &vk_cb);

    vkd.destroyBuffer(core.device, self.glyph_ssbo.handle, &vk_cb);
    vkd.destroyBuffer(core.device, self.style_ssbo.handle, &vk_cb);

    // Free device memory through allocator
    self.device_allocator.free(core, self.vertex_buffer.memory);
    self.device_allocator.free(core, self.staging_buffer.memory);
    self.device_allocator.free(core, self.uniform_buffer.memory);

    self.device_allocator.free(core, self.glyph_ssbo.memory);
    self.device_allocator.free(core, self.style_ssbo.memory);
}

pub fn createBuffer(
    core: *const Core,
    device_alloc: *DeviceAllocator,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    mem_props: vk.MemoryPropertyFlags,
) !BufferResource {
    const vk_mem_cb = core.alloc_callbacks();

    // Create the Vulkan buffer
    const buffer_create_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };
    const buffer = try core.vkd().createBuffer(core.device, &buffer_create_info, vk_mem_cb);

    // Get memory requirements
    const mem_reqs = core.vkd().getBufferMemoryRequirements(core.device, buffer);

    // Allocate with your device allocator
    const dev_alloc = try device_alloc.alloc(
        core,
        @intCast(mem_reqs.size),
        mem_reqs.memory_type_bits,
        mem_props,
    );

    // Bind memory
    try core.vkd().bindBufferMemory(core.device, buffer, dev_alloc.memory, dev_alloc.offset);

    return .{
        .handle = buffer,
        .memory = dev_alloc,
    };
}

pub fn stageVertexData(
    self: *Buffers,
    core: *const Core,
    grid: *const Grid,
) !void {
    const data_size = grid.data().len * @sizeOf(Cell);
    if (data_size > self.staging_buffer.memory.size) {
        try self.staging_buffer.memory.unmap(core);
        _ = try self.device_allocator.resize(core, &self.staging_buffer.memory, data_size);
        try self.staging_buffer.memory.map(core);
    }

    var host_slice_ptr = self.staging_buffer.memory.hostSlicePtr(Cell) orelse blk: {
        try self.staging_buffer.memory.map(core);
        break :blk self.staging_buffer.memory.hostSlicePtr(Cell).?;
    };
    const host_slice = host_slice_ptr[0..grid.data().len];

    @memcpy(host_slice, grid.data());
}

pub var uniform_buffer_ptr: ?*UniformsBlock = null;

pub fn updateUniformData(
    self: *const Buffers,
    core: *const Core,
    data: *const UniformsBlock,
) !void {
    const vkd = &core.dispatch.vkd;

    const ptr = try vkd.mapMemory(
        core.device,
        self.uniform_buffer.memory.memory,
        0,
        @sizeOf(UniformsBlock),
        .{},
    );
    // defer vkd.unmapMemory(core.device, self.uniform_buffer.memory);

    @as(*UniformsBlock, @ptrCast(@alignCast(ptr))).* = data.*;
    uniform_buffer_ptr = @ptrCast(@alignCast(ptr));
}

pub fn updateSSBOs(
    self: *Buffers,
    core: *const Core,
    atlas: *const Atlas,
) !void {
    const glyph_data_count = atlas.glyph_lookup_map.values().len;
    const glyph_data_size = glyph_data_count * @sizeOf(Atlas.GlyphInfo);
    if (self.glyph_ssbo.memory.size < glyph_data_size) {
        try self.glyph_ssbo.memory.unmap(core);
        _ = try self.device_allocator.resize(core, &self.glyph_ssbo.memory, glyph_data_size);
    }

    const glyph_metrics_ssbo_ptr = self.glyph_ssbo.memory.hostSlicePtr(Atlas.GlyphInfo) orelse blk: {
        try self.glyph_ssbo.memory.map(core);
        break :blk self.glyph_ssbo.memory.hostSlicePtr(Atlas.GlyphInfo).?;
    };

    @memcpy(glyph_metrics_ssbo_ptr[0..glyph_data_count], atlas.glyph_lookup_map.values());

    const style_ssbo_ptr = self.style_ssbo.memory.hostSlicePtr(Grid.CellStyle) orelse blk: {
        try self.style_ssbo.memory.map(core);
        break :blk self.style_ssbo.memory.hostSlicePtr(Grid.CellStyle).?;
    };

    @memset(style_ssbo_ptr[0..64], .{
        .fg_color = .White,
        .bg_color = .Black,
    });
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

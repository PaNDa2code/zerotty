const Resources = @This();

// VIBE-CODED

// Vulkan descriptor management
descriptor_pool: core.DescriptorPool,
descriptor_layout: core.DescriptorSetLayout,
descriptor_set: core.DescriptorSet,

// Terminal rendering resources
uniform_buffer: core.Buffer, // Screen/cell dimensions
vertex_buffer: core.Buffer, // Quad vertices
cell_data_buffer: core.Buffer, // Cell character data
style_data_buffer: core.Buffer, // Cell style/color data
font_atlas: core.Image, // Font texture atlas
font_sampler: core.Sampler, // Font atlas sampler

// Resource capacities
max_cells: usize,
max_styles: usize,

pub fn init(
    allocator: std.mem.Allocator,
    device: *const core.Device,
    vram_allocator: *core.memory.DeviceAllocator,
    max_cells: usize,
    max_styles: usize,
    font_atlas_width: u32,
    font_atlas_height: u32,
) !Resources {
    // Create descriptor pool for terminal resources
    const descriptor_pool = try core.DescriptorPool.Builder
        .addPoolSize(.uniform_buffer, 1)
        .addPoolSize(.storage_buffer, 3)
        .addPoolSize(.combined_image_sampler, 1)
        .build(device);
    errdefer descriptor_pool.deinit();

    // Create descriptor set layout
    const descriptor_layout = try core.DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .addBinding(2, .storage_buffer, 1, .{ .vertex_bit = true })
        .addBinding(3, .storage_buffer, 1, .{ .vertex_bit = true })
        .build(device);
    errdefer descriptor_layout.deinit(device);

    // Create uniform buffer for screen/cell dimensions
    const uniform_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.Uniforms),
        .{ .uniform_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer uniform_buffer.deinit(vram_allocator);

    // Create vertex buffer for quad rendering
    var vertex_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.Vertex) * 4, // 4 vertices per quad
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer vertex_buffer.deinit(vram_allocator);

    // Create cell data storage buffer
    const cell_data_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.Instance) * max_cells,
        .{ .storage_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer cell_data_buffer.deinit(vram_allocator);

    // Create style data storage buffer
    const style_data_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.GlyphStyle) * max_styles,
        .{ .storage_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer style_data_buffer.deinit(vram_allocator);

    // Create font atlas image
    var image_builder = core.Image.Builder.new();
    const font_atlas = try image_builder
        .setFormat(.r8_unorm)
        .setSize(font_atlas_width, font_atlas_height)
        .addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true })
        .asTexture()
        .build(vram_allocator);
    errdefer font_atlas.deinit(vram_allocator);

    // Create font sampler
    const font_sampler = try core.Sampler.init(device);
    errdefer font_sampler.deinit(device);

    // Prepare descriptor infos
    const uniform_buffer_info = uniform_buffer.getDescriptorBufferInfo();
    // const font_atlas_info = font_atlas.getDescriptorImageInfo(&font_sampler);
    const cell_data_info = cell_data_buffer.getDescriptorBufferInfo();
    const style_data_info = style_data_buffer.getDescriptorBufferInfo();

    const descriptor_info = try allocator.alloc([]vk.DescriptorBufferInfo, 3);
    descriptor_info[0] = try allocator.alloc(vk.DescriptorBufferInfo, 1);
    descriptor_info[1] = try allocator.alloc(vk.DescriptorBufferInfo, 1);
    descriptor_info[2] = try allocator.alloc(vk.DescriptorBufferInfo, 1);

    descriptor_info[0][0] = uniform_buffer_info;
    descriptor_info[1][0] = cell_data_info;
    descriptor_info[2][0] = style_data_info;

    // Create descriptor set with all bindings
    const descriptor_set = try core.DescriptorSet.init(
        &descriptor_pool,
        &descriptor_layout,
        allocator,
        descriptor_info,
        &.{},
        // &.{&.{font_atlas_info}},
    );

    // Initialize vertex buffer with basic quad
    if (vertex_buffer.hostSlice(vertex.Vertex)) |vertices| {
        vertices[0] = .{ .quad_vertex = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 } }; // Top-left
        vertices[1] = .{ .quad_vertex = .{ .x = 1.0, .y = 0.0, .z = 0.0, .w = 1.0 } }; // Top-right
        vertices[2] = .{ .quad_vertex = .{ .x = 1.0, .y = 1.0, .z = 0.0, .w = 1.0 } }; // Bottom-right
        vertices[3] = .{ .quad_vertex = .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 1.0 } }; // Bottom-left
    }

    return .{
        .descriptor_pool = descriptor_pool,
        .descriptor_layout = descriptor_layout,
        .descriptor_set = descriptor_set,
        .uniform_buffer = uniform_buffer,
        .vertex_buffer = vertex_buffer,
        .cell_data_buffer = cell_data_buffer,
        .style_data_buffer = style_data_buffer,
        .font_atlas = font_atlas,
        .font_sampler = font_sampler,
        .max_cells = max_cells,
        .max_styles = max_styles,
    };
}

pub fn deinit(self: *Resources, device: *const core.Device, vram_allocator: *core.memory.DeviceAllocator, allocator: std.mem.Allocator) void {
    for (self.descriptor_set.buffer_infos) |arr| {
        allocator.free(arr);
    }
    self.descriptor_layout.deinit(device);
    self.descriptor_pool.deinit();

    self.uniform_buffer.deinit(vram_allocator);
    self.vertex_buffer.deinit(vram_allocator);
    self.cell_data_buffer.deinit(vram_allocator);
    self.style_data_buffer.deinit(vram_allocator);
    self.font_atlas.deinit(vram_allocator);
    self.font_sampler.deinit(device);
}

pub fn updateUniforms(self: *Resources, screen_width: f32, screen_height: f32, cell_width: f32, cell_height: f32) !void {
    if (self.uniform_buffer.hostSlice(vertex.Uniforms)) |uniforms| {
        uniforms.* = .{
            .cell_height = cell_height,
            .cell_width = cell_width,
            .screen_height = screen_height,
            .screen_width = screen_width,
            .atlas_cols = @as(f32, @floatFromInt(self.font_atlas.extent.width / cell_width)),
            .atlas_rows = @as(f32, @floatFromInt(self.font_atlas.extent.height / cell_height)),
            .atlas_width = @as(f32, @floatFromInt(self.font_atlas.extent.width)),
            .atlas_height = @as(f32, @floatFromInt(self.font_atlas.extent.height)),
            .descender = 0.0, // TODO: Get from font metrics
        };
    }
}

pub fn updateCellData(self: *Resources, cell_instances: []const vertex.Instance) !void {
    if (cell_instances.len > self.max_cells) return error.TooManyCells;

    if (self.cell_data_buffer.hostSlice(vertex.Instance)) |cell_data| {
        @memcpy(cell_data[0..cell_instances.len], cell_instances);
    }
}

pub fn updateStyleData(self: *Resources, style_data: []const vertex.GlyphStyle) !void {
    if (style_data.len > self.max_styles) return error.TooManyStyles;

    if (self.style_data_buffer.hostSlice(vertex.GlyphStyle)) |styles| {
        @memcpy(styles[0..style_data.len], style_data);
    }
}

pub fn updateFontAtlas(self: *Resources, cmd_buffer: *const core.CommandBuffer, font_data: []const u8) !void {
    // Create staging buffer for font upload
    const staging_buffer = try core.Buffer.initAlloc(
        cmd_buffer.pool.device_allocator,
        font_data.len,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    defer staging_buffer.deinit(cmd_buffer.pool.device_allocator);

    // Copy font data to staging buffer
    if (staging_buffer.hostSlice(u8)) |staging| {
        @memcpy(staging, font_data);
    }

    // Record copy command
    try cmd_buffer.copyBufferToImage(staging_buffer.handle, self.font_atlas.handle);
}

pub fn bind(self: *const Resources, cmd_buffer: *const core.CommandBuffer, pipeline_layout: *const core.PipelineLayout) void {
    cmd_buffer.bindDescriptorSets(
        pipeline_layout.handle,
        0, // set number
        1, // set count
        &.{self.descriptor_set.handle},
    );
}

pub fn bindVertexBuffers(self: *const Resources, cmd_buffer: *const core.CommandBuffer) void {
    cmd_buffer.bindVertexBuffers(0, &.{self.vertex_buffer.handle});
}

pub fn getCellCount(self: *const Resources) usize {
    return self.max_cells;
}

pub fn getStyleCount(self: *const Resources) usize {
    return self.max_styles;
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");
const vertex = @import("vertex.zig");

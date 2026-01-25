const Resources = @This();

pool: core.DescriptorPool,
layout: core.DescriptorSetLayout,
set: core.DescriptorSet,

// Descriptor bindings for terminal rendering
uniform_buffer: core.Buffer, // Binding 0: Screen/cell dimensions
vertex_buffer: core.Buffer, // Binding for vertex data
glyph_data_buffer: core.Buffer, // Binding 2: GlyphMetrics
style_data_buffer: core.Buffer, // Binding 3: Cell style/color data
font_atlas: core.Image, // Binding 1: Font texture atlas
font_sampler: core.Sampler, // Font atlas sampler

staging_buffer: core.Buffer,

descriptor_buffer_infos: *std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)),
descriptor_image_infos: *std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)),

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
    const pool = try core.DescriptorPool.Builder
        .addPoolSize(.uniform_buffer, 1)
        .addPoolSize(.storage_buffer, 2)
        .addPoolSize(.combined_image_sampler, 1)
        .build(device);
    errdefer pool.deinit();

    // Create descriptor set layout
    const layout = try core.DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .addBinding(2, .storage_buffer, 1, .{ .vertex_bit = true })
        .addBinding(3, .storage_buffer, 1, .{ .vertex_bit = true })
        .build(device);
    errdefer layout.deinit(device);

    // Create uniform buffer for screen/cell dimensions
    const uniform_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        try std.math.ceilPowerOfTwo(usize, @sizeOf(vertex.Uniforms)),
        .{ .uniform_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer uniform_buffer.deinit(vram_allocator);

    // Create vertex buffer for basic quad rendering
    const vertex_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.Instance) * max_cells,
        .{ .vertex_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer vertex_buffer.deinit(vram_allocator);

    // Create style data storage buffer
    const glyph_data_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.GlyphMetrics) * 512,
        .{ .storage_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer glyph_data_buffer.deinit(vram_allocator);

    const style_data_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        @sizeOf(vertex.GlyphStyle) * max_styles,
        .{ .storage_buffer_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer style_data_buffer.deinit(vram_allocator);

    // Create staging buffer for font upload
    const staging_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        font_atlas_width * font_atlas_height,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    errdefer staging_buffer.deinit(vram_allocator);

    // Create font atlas image
    var image_builder = core.Image.Builder.new();
    const font_atlas = try image_builder
        .setFormat(.r8_unorm)
        .setSize(font_atlas_width, font_atlas_height)
        .addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true })
        .setMipLevels(1)
        .build(vram_allocator);

    errdefer font_atlas.deinit(vram_allocator);

    // Create font sampler
    const font_sampler = try core.Sampler.init(device);
    errdefer font_sampler.deinit(device);

    // Create descriptor set with all bindings
    const uniform_buffer_info = uniform_buffer.getDescriptorBufferInfo();
    const font_atlas_info = font_atlas.getDescriptorImageInfo(font_sampler.handle);
    const style_data_info = style_data_buffer.getDescriptorBufferInfo();
    const glyph_data_info = glyph_data_buffer.getDescriptorBufferInfo();

    const buffer_infos = try allocator.create(std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)));
    const image_infos = try allocator.create(std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)));

    buffer_infos.* = .init(allocator);
    image_infos.* = .init(allocator);

    {
        const uniform_entry = try buffer_infos.getOrPutValue(0, .empty);
        try uniform_entry.value_ptr.append(allocator, uniform_buffer_info);

        const font_atlas_entry = try image_infos.getOrPutValue(1, .empty);
        try font_atlas_entry.value_ptr.append(allocator, font_atlas_info);

        const glyph_data_entry = try buffer_infos.getOrPutValue(2, .empty);
        try glyph_data_entry.value_ptr.append(allocator, glyph_data_info);

        const style_data_entry = try buffer_infos.getOrPutValue(3, .empty);
        try style_data_entry.value_ptr.append(allocator, style_data_info);
    }

    var set = try core.DescriptorSet.init(
        &pool,
        &layout,
        allocator,
        buffer_infos,
        image_infos,
    );

    set.update();

    return .{
        .pool = pool,
        .layout = layout,
        .set = set,
        .uniform_buffer = uniform_buffer,
        .vertex_buffer = vertex_buffer,
        .glyph_data_buffer = glyph_data_buffer,
        .style_data_buffer = style_data_buffer,
        .staging_buffer = staging_buffer,
        .font_atlas = font_atlas,
        .font_sampler = font_sampler,
        .descriptor_buffer_infos = buffer_infos,
        .descriptor_image_infos = image_infos,
        .max_cells = max_cells,
        .max_styles = max_styles,
    };
}

pub fn deinit(self: *Resources, device: *const core.Device, vram_allocator: *core.memory.DeviceAllocator, allocator: std.mem.Allocator) void {
    self.layout.deinit(device);
    self.pool.deinit();

    self.uniform_buffer.deinit(vram_allocator);
    self.vertex_buffer.deinit(vram_allocator);
    self.glyph_data_buffer.deinit(vram_allocator);
    self.style_data_buffer.deinit(vram_allocator);
    self.staging_buffer.deinit(vram_allocator);
    self.font_atlas.deinit(vram_allocator);
    self.font_sampler.deinit(device);

    var buffer_iter = self.descriptor_buffer_infos.valueIterator();
    while (buffer_iter.next()) |list| {
        list.deinit(allocator);
    }
    var image_iter = self.descriptor_image_infos.valueIterator();
    while (image_iter.next()) |list| {
        list.deinit(allocator);
    }

    self.descriptor_buffer_infos.deinit();
    self.descriptor_image_infos.deinit();

    allocator.destroy(self.descriptor_buffer_infos);
    allocator.destroy(self.descriptor_image_infos);

    self.set.write_descriptor_sets.deinit(allocator);
}

// Update functions for modifying data
pub fn updateUniforms(self: *Resources, screen_width: f32, screen_height: f32, cell_width: f32, cell_height: f32) !void {
    if (self.uniform_buffer.hostPtr(vertex.Uniforms)) |uniforms| {
        uniforms.* = .{
            .cell_height = cell_height,
            .cell_width = cell_width,
            .screen_height = screen_height,
            .screen_width = screen_width,
            .atlas_cols = @as(f32, @floatFromInt(self.font_atlas.extent.width)) / cell_width,
            .atlas_rows = @as(f32, @floatFromInt(self.font_atlas.extent.height)) / cell_height,
            .atlas_width = @as(f32, @floatFromInt(self.font_atlas.extent.width)),
            .atlas_height = @as(f32, @floatFromInt(self.font_atlas.extent.height)),
            .descender = 0.0, // TODO: Get from font metrics
        };
    }
}

pub fn updateVertexInstances(self: *Resources, cell_instances: []const vertex.Instance) !void {
    if (cell_instances.len > self.max_cells) return error.TooManyCells;

    if (self.vertex_buffer.hostSlice(vertex.Instance)) |cell_data| {
        @memcpy(cell_data[0..cell_instances.len], cell_instances);
    }
}

pub fn updateGlyphData(self: *Resources, metrics: []const vertex.GlyphMetrics) !void {
    if (self.glyph_data_buffer.hostSlice(vertex.GlyphMetrics)) |glyph_data| {
        @memcpy(glyph_data[0..metrics.len], metrics);
    }
}

pub fn updateStyleData(self: *Resources, style_data: []const vertex.GlyphStyle) !void {
    if (style_data.len > self.max_styles) return error.TooManyStyles;

    if (self.style_data_buffer.hostSlice(vertex.GlyphStyle)) |styles| {
        @memcpy(styles[0..style_data.len], style_data);
    }
}

// Update descriptor set with new data
pub fn updateDescriptorSet(self: *Resources) !void {
    try self.set.prepare();
    self.set.update();
}

// Binding functions for rendering
pub fn bindResources(self: *Resources, cmd_buffer: *core.CommandBuffer, pipeline_layout: vk.PipelineLayout) !void {
    // Bind vertex buffer
    try cmd_buffer.bindVertexBuffer(&self.vertex_buffer, 0);

    // Bind descriptor set
    try cmd_buffer.bindDescriptorSet(&self.set, pipeline_layout);
}

pub fn bindVertexBuffers(self: *Resources, cmd_buffer: *core.CommandBuffer) !void {
    try cmd_buffer.bindVertexBuffer(&self.vertex_buffer, 0);
}

pub fn getCellCount(self: *const Resources) usize {
    return self.max_cells;
}

pub fn getStyleCount(self: *const Resources) usize {
    return self.max_styles;
}

// Font atlas upload function
pub fn uploadFontAtlas(
    self: *Resources,
    cmd_buffer: *core.CommandBuffer,
    queue: *const core.Queue,
    fence: vk.Fence,
    device_allocator: *core.memory.DeviceAllocator,
    font_data: []const u8,
    font_atlas_height: u32,
    font_atlas_width: u32,
) !void {
    if (self.staging_buffer.mem_alloc.?.size < font_data.len) {
        self.staging_buffer.deinit(device_allocator);

        self.staging_buffer = try core.Buffer.initAlloc(
            device_allocator,
            font_data.len,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );
    }

    // Copy font data to staging buffer
    if (self.staging_buffer.hostSlice(u8)) |staging| {
        @memcpy(staging, font_data);
    }

    var arina = std.heap.ArenaAllocator.init(device_allocator.std_allocator);
    defer arina.deinit();

    try cmd_buffer.reset(true);
    try cmd_buffer.begin(.{ .one_time_submit_bit = true });

    try transitionImageLayout(
        cmd_buffer,
        self.font_atlas.handle,
        .{ .color_bit = true },
        .undefined,
        .transfer_dst_optimal,
        arina.allocator(),
    );

    const copy_regon = [_]vk.BufferImageCopy{.{
        .buffer_offset = 0,
        .buffer_row_length = font_atlas_width,
        .buffer_image_height = font_atlas_height,
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{
            .height = self.font_atlas.extent.height,
            .width = self.font_atlas.extent.width,
            .depth = 1,
        },
    }};

    try cmd_buffer.copyBufferToImage(
        self.staging_buffer.handle,
        self.font_atlas.handle,
        .transfer_dst_optimal,
        &copy_regon,
    );

    try transitionImageLayout(
        cmd_buffer,
        self.font_atlas.handle,
        .{ .color_bit = true },
        .transfer_dst_optimal,
        .shader_read_only_optimal,
        arina.allocator(),
    );

    try cmd_buffer.end();

    try queue.submitOne(cmd_buffer, .null_handle, .null_handle, .{}, fence);

    _ = try cmd_buffer.device.waitFence(fence, std.math.maxInt(u64));
}

fn transitionImageLayout(
    cmd_buffer: *core.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    arina: std.mem.Allocator,
) !void {
    var src_access_mask: vk.AccessFlags2 = .{};
    var dst_access_mask: vk.AccessFlags2 = .{};
    var src_stage_mask: vk.PipelineStageFlags2 = .{};
    var dst_stage_mask: vk.PipelineStageFlags2 = .{};

    switch (old_layout) {
        .undefined, .preinitialized => {
            src_access_mask = .{};
            src_stage_mask.top_of_pipe_bit = true;
        },
        .transfer_dst_optimal => {
            src_access_mask.transfer_write_bit = true;
            src_stage_mask.all_transfer_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.shader_read_bit = true;
            src_stage_mask.all_graphics_bit = true;
        },
        else => {},
    }

    switch (new_layout) {
        .transfer_dst_optimal => {
            dst_access_mask.transfer_write_bit = true;
            dst_stage_mask.all_transfer_bit = true;
        },
        .shader_read_only_optimal => {
            dst_access_mask.shader_read_bit = true;
            dst_stage_mask.fragment_shader_bit = true;
        },
        else => {},
    }

    const barriers = [_]vk.ImageMemoryBarrier2{.{
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .src_stage_mask = src_stage_mask,
        .dst_stage_mask = dst_stage_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = aspects,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};

    try cmd_buffer.pipelineBarrierAuto(
        arina,
        .{
            .src_stage_mask = src_stage_mask,
            .dst_stage_mask = dst_stage_mask,
            .image_barriers = &barriers,
        },
    );
}
const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");
const vertex = @import("vertex.zig");

const Renderer = @This();

pub const InitError = anyerror;

render_context: RenderContext,
render_pipeline: RenderPipeline,
frame_manager: FrameManager,

swapchain_target: *SwapchainTarget,
render_target: RenderTarget,

cache: Cache,
staging_buffer: core.Buffer,
glyph_staging_buffer: core.Buffer,

bg_color_image: core.Image,
bg_color_sampler: core.Sampler,
bg_color_staging: core.Buffer,
bg_color_staging_capacity: usize = 0,
bg_grid_cols: u32 = 1,
bg_grid_rows: u32 = 1,
bg_color_layout: vk.ImageLayout = .undefined,
bg_color_ready: bool = false,

settings: root.RendererSettings,

current_frame: ?*FrameManager.FrameResources,
frame_info: ?RenderTarget.FrameInfo,

bg_color: color.RGBA,

instance_count: u32 = 0,

pub fn init(
    allocator: std.mem.Allocator,
    window_handles: platform.WindowNativeHandles,
    _: platform.WindowRendererRequirements,
    settings: root.RendererSettings,
) InitError!Renderer {
    const render_context = try RenderContext.init(allocator, window_handles);

    const swapchain_target_ptr = try allocator.create(SwapchainTarget);
    errdefer allocator.destroy(swapchain_target_ptr);

    swapchain_target_ptr.* = try SwapchainTarget.init(
        render_context.instance,
        render_context.device,
        allocator,
        render_context.surface,
        .{
            .image_count = 2,
            .extent = .{
                .height = settings.surface_height,
                .width = settings.surface_width,
            },
        },
        2,
    );

    const frame_manager = try FrameManager.init(
        render_context.device,
        render_context.device_allocator,
        allocator,
        2,
    );

    const render_pipeline = try RenderPipeline.init(
        allocator,
        render_context.device,
        .{
            .image_attachemnt_format = swapchain_target_ptr.swapchain.surface_format.format,
            .extent = swapchain_target_ptr.swapchain.extent,
            .final_layout = .present_src_khr,
        },
        .{ .descriptor_set_layouts = frame_manager.descriptor_layouts },
    );

    try swapchain_target_ptr.ensureFramebuffers(&render_pipeline.renderpass);

    const render_target = swapchain_target_ptr.interface();

    // see src/font/root.zig
    var cache = Cache.init(2048, 2048, 255);
    _ = try cache.newTexture(allocator, render_context.device_allocator);

    const staging_buffer = try core.Buffer.initAlloc(
        render_context.device_allocator,
        2048 * 2048,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );

    const glyph_staging_buffer = try core.Buffer.initAlloc(
        render_context.device_allocator,
        2048 * 2048,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );

    const bg_grid_cols = @max(1, settings.grid_cols);
    const bg_grid_rows = @max(1, settings.grid_rows);

    var bg_image_builder = core.Image.Builder.new();
    const bg_color_image = try bg_image_builder
        .setFormat(.r8g8b8a8_unorm)
        .setSize(bg_grid_cols, bg_grid_rows)
        .addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true })
        .build(render_context.device_allocator);

    const bg_color_sampler = try core.Sampler.init(render_context.device, .{
        .filter = .nearest,
        .address_mode = .clamp_to_edge,
        .mipmap_mode = .nearest,
    });

    const bg_color_staging = try core.Buffer.initAlloc(
        render_context.device_allocator,
        1024 * 1024,
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );

    return .{
        .render_context = render_context,
        .render_pipeline = render_pipeline,
        .swapchain_target = swapchain_target_ptr,
        .render_target = render_target,
        .frame_manager = frame_manager,
        .cache = cache,
        .staging_buffer = staging_buffer,
        .glyph_staging_buffer = glyph_staging_buffer,
        .bg_color_image = bg_color_image,
        .bg_color_sampler = bg_color_sampler,
        .bg_color_staging = bg_color_staging,
        .bg_color_staging_capacity = 1024 * 1024,
        .bg_grid_cols = bg_grid_cols,
        .bg_grid_rows = bg_grid_rows,
        .settings = settings,
        .current_frame = null,
        .frame_info = null,
        .bg_color = .black,
    };
}

pub fn deinit(self: *Renderer) void {
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;

    device.waitIdle() catch {};

    self.render_target.deinit();
    allocator.destroy(self.swapchain_target);
    self.staging_buffer.deinit(self.render_context.device_allocator);
    self.glyph_staging_buffer.deinit(self.render_context.device_allocator);
    self.bg_color_staging.deinit(self.render_context.device_allocator);
    self.bg_color_image.deinit(self.render_context.device_allocator);
    self.bg_color_sampler.deinit(self.render_context.device);
    self.cache.deinit(allocator, self.render_context.device_allocator);
    self.frame_manager.deinit(allocator);

    self.render_pipeline.deinit(device, allocator);
    self.render_context.deinit();
}

pub fn beginFrame(self: *Renderer) !void {
    const frame = self.frame_manager.beginFrame() catch |err| {
        return err;
    };
    self.current_frame = frame;

    self.frame_info = self.render_target.acquireFrame(frame.in_flight_fence) catch |err| blk: {
        if (err == error.TargetNotReady) {
            try self.resizeSurface(0, 0);
            break :blk try self.render_target.acquireFrame(frame.in_flight_fence);
        }
        return err;
    };
    const info = self.frame_info.?;

    const cmd = &frame.main_cmd;

    try cmd.begin(.{ .one_time_submit_bit = true });

    try frame.descriptor_sets[0].reset();
    try frame.descriptor_sets[0].addDescriptor(0, 0, .{
        .buffer = frame.uniform_buffer.getDescriptorBufferInfo(),
    });
    try frame.descriptor_sets[0].addDescriptor(1, 0, .{
        .image = self.bg_color_image.getDescriptorImageInfo(self.bg_color_sampler),
    });
    frame.descriptor_sets[0].update();

    try self.cache.updateDescriptorSet(&frame.descriptor_sets[1]);

    try cmd.bindPipeline(self.render_pipeline.pipeline.handle, .graphics);

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(info.extent.width),
        .height = @floatFromInt(info.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    try cmd.setViewPort(viewport);

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = info.extent,
    };
    try cmd.setScissor(scissor);
}

pub fn endFrame(self: *Renderer) !void {
    if (self.current_frame) |frame| {
        const info = self.frame_info orelse return error.FrameDidNotStart;

        const staging_uniform_ptr = self.frame_manager.uniform_stage
            .hostPtr(vertex.TextUniform) orelse unreachable;

        const screen_w: f32 = @floatFromInt(info.extent.width);
        const screen_h: f32 = @floatFromInt(info.extent.height);

        const atlas_w: f32 = 2048;
        const atlas_h: f32 = 2048;

        const cell_w: f32 = @floatFromInt(self.settings.cell_width);
        const cell_h: f32 = @floatFromInt(self.settings.cell_height);
        const baseline: f32 =
            if (self.settings.baseline > 0)
                @floatFromInt(self.settings.baseline)
            else
                cell_h * (7.0 / 8.0);

        staging_uniform_ptr.* = vertex.TextUniform{
            .screen_to_clip_scale = .from(2.0 / screen_w, 2.0 / screen_h),
            .screen_to_clip_offset = .from(-1.0, -1.0),
            .inv_atlas_size = .from(1.0 / atlas_w, 1.0 / atlas_h),
            .cell_size = .from(cell_w, cell_h),
            .cell_size_inv = .from(1.0 / cell_w, 1.0 / cell_h),
            .grid_size = .from(@floatFromInt(self.bg_grid_cols), @floatFromInt(self.bg_grid_rows)),
            .baseline = baseline,
        };

        try frame.main_cmd.copyBuffer(
            self.frame_manager.uniform_stage.handle,
            frame.uniform_buffer.handle,
            &.{
                .{
                    .src_offset = 0,
                    .dst_offset = 0,
                    .size = @sizeOf(vertex.TextUniform),
                },
            },
        );

        for (0..2) |i| {
            try frame.descriptor_sets[i].prepare();
            frame.descriptor_sets[i].update();
        }

        if (self.instance_count != 0 or self.bg_color_ready) {
            for (0..2) |i|
                try frame.main_cmd.bindDescriptorSet(
                    &frame.descriptor_sets[i],
                    @intCast(i),
                    self.render_pipeline.pipeline_layout.handle,
                );

            const clear_values = [_]vk.ClearValue{
                .{ .color = .{ .float_32 = self.bg_color.floatArray() } },
            };

            try frame.main_cmd.beginRenderPass(
                &self.render_pipeline.renderpass,
                info.framebuffer,
                &clear_values,
                .@"inline",
            );

            if (self.bg_color_ready) {
                try frame.main_cmd.bindPipeline(self.render_pipeline.bg_pass_pipeline.handle, .graphics);

                try frame.main_cmd.draw(3, 1, 0, 0);
            }

            if (self.instance_count != 0) {
                try frame.main_cmd.bindPipeline(self.render_pipeline.pipeline.handle, .graphics);

                try frame.main_cmd.bindVertexBuffer(
                    &frame.vertex_buffer,
                    0,
                );

                try frame.main_cmd.draw(6, self.instance_count, 0, 0);
            }

            try frame.main_cmd.endRenderPass();
        }

        try frame.main_cmd.end();
    } else return error.FrameDidNotStart;
}

pub fn presnt(self: *Renderer) !void {
    if (self.current_frame) |frame| {
        self.render_target.presentFrame(.{
            .queue = &self.render_context.queue,
            .cmd = &frame.main_cmd,
            .in_flight_fence = frame.in_flight_fence,
        }) catch {};
    }
    self.frame_manager.advanceFrame();
    self.current_frame = null;
    self.frame_info = null;
    self.instance_count = 0;
}

pub fn clear(self: *Renderer, bg_color: color.RGBA) void {
    self.bg_color = bg_color;
}

pub fn setViewport(self: *Renderer, x: u32, y: u32, width: u32, height: u32) !void {
    const viewport = vk.Viewport{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(width),
        .height = @floatFromInt(height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = width, .height = height },
    };

    if (self.current_frame) |frame| {
        try frame.main_cmd.setViewPort(viewport);
        try frame.main_cmd.setScissor(scissor);
    }
}

pub fn resizeSurface(self: *Renderer, width: u32, height: u32) !void {
    try self.render_context.device.waitIdle();

    const new_extent = try self.render_context.getSurfaceExtent(width, height);

    if (self.swapchain_target.swapchain.extent.width == new_extent.width and
        self.swapchain_target.swapchain.extent.height == new_extent.height)
    {
        return;
    }

    try self.swapchain_target.recreate(
        self.render_context.allocator_adapter.allocator,
        new_extent,
    );

    try self.swapchain_target.ensureFramebuffers(&self.render_pipeline.renderpass);
}

pub fn resetGlyphCache(self: *Renderer) !void {
    try self.render_context.device.waitIdle();

    const allocator = self.render_context.allocator_adapter.allocator;
    self.cache.deinit(allocator, self.render_context.device_allocator);

    var cache = Cache.init(2048, 2048, 255);
    _ = try cache.newTexture(allocator, self.render_context.device_allocator);

    self.cache = cache;
}

pub fn cacheGlyphs(
    self: *Renderer,
    entries: []font.GlyphAtlasEntry,
    bitmap_pool: []const u8,
) !void {
    const frame = self.current_frame orelse return error.FrameDidNotStart;

    if (self.glyph_staging_buffer.mem_alloc == null or
        self.glyph_staging_buffer.mem_alloc.?.size < bitmap_pool.len)
    {
        self.glyph_staging_buffer.deinit(self.render_context.device_allocator);
        self.glyph_staging_buffer = try .initAlloc(
            self.render_context.device_allocator,
            bitmap_pool.len,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );
    }

    const stage_slice = self.glyph_staging_buffer.hostSlice(u8) orelse
        return error.MemoryMapFailed;
    @memcpy(stage_slice[0..bitmap_pool.len], bitmap_pool);

    try self.cache.recordCopyCmd(
        &frame.main_cmd,
        &self.glyph_staging_buffer,
        self.render_context.allocator_adapter.allocator,
        entries,
    );
}

pub fn reserveBatch(self: *Renderer, count: usize) ![]vertex.TextInstance {
    if (self.staging_buffer.mem_alloc == null or
        self.staging_buffer.mem_alloc.?.size < count * @sizeOf(vertex.TextInstance))
    {
        self.staging_buffer.deinit(self.render_context.device_allocator);
        self.staging_buffer = try .initAlloc(
            self.render_context.device_allocator,
            count * @sizeOf(vertex.TextInstance),
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );
    }

    return self.staging_buffer.hostSlice(vertex.TextInstance).?[0..count];
}

pub fn commitBatch(self: *Renderer, count: usize) !void {
    if (self.current_frame) |frame| {
        if (frame.vertex_buffer.mem_alloc == null or
            frame.vertex_buffer.mem_alloc.?.size < count * @sizeOf(vertex.TextInstance))
        {
            frame.vertex_buffer.deinit(self.render_context.device_allocator);

            frame.vertex_buffer = try .initAlloc(
                self.render_context.device_allocator,
                count * @sizeOf(vertex.TextInstance),
                .{ .transfer_dst_bit = true },
                .{ .device_local_bit = true },
                .exclusive,
            );
        }
        const copy_regons = [_]vk.BufferCopy{
            .{
                .src_offset = 0,
                .dst_offset = 0,
                .size = count * @sizeOf(vertex.TextInstance),
            },
        };

        try frame.main_cmd.copyBuffer(
            self.staging_buffer.handle,
            frame.vertex_buffer.handle,
            &copy_regons,
        );

        try frame.main_cmd.bindVertexBuffer(
            &frame.vertex_buffer,
            0,
        );
    } else return error.FrameDidNotStart;

    self.instance_count = @intCast(count);
}

/// Recreate the per-cell background color texture for the new grid
/// dimensions. Callers must follow up with `uploadBackground` to
/// repopulate the texture before it is sampled again.
pub fn setGridSize(self: *Renderer, cols: u32, rows: u32) !void {
    const new_cols = @max(1, cols);
    const new_rows = @max(1, rows);

    if (self.bg_grid_cols == new_cols and self.bg_grid_rows == new_rows)
        return;

    try self.render_context.device.waitIdle();

    self.bg_color_image.deinit(self.render_context.device_allocator);

    var bg_image_builder = core.Image.Builder.new();
    self.bg_color_image = try bg_image_builder
        .setFormat(.r8g8b8a8_unorm)
        .setSize(new_cols, new_rows)
        .addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true })
        .build(self.render_context.device_allocator);

    self.bg_grid_cols = new_cols;
    self.bg_grid_rows = new_rows;
    self.bg_color_layout = .undefined;
    self.bg_color_ready = false;
}

/// Stage `colors` (`rows * cols * 4` RGBA8 bytes) into the per-cell
/// background texture. Must be called between `beginFrame`/`endFrame`.
pub fn uploadBackground(self: *Renderer, rows: u32, cols: u32, colors: []const u8) !void {
    const frame = self.current_frame orelse return error.FrameDidNotStart;
    if (rows == 0 or cols == 0) return;

    const need: usize = @as(usize, rows) * @as(usize, cols) * 4;
    if (colors.len < need) return error.BackgroundDataTooShort;

    if (self.bg_color_staging_capacity < need) {
        self.bg_color_staging.deinit(self.render_context.device_allocator);
        self.bg_color_staging = try .initAlloc(
            self.render_context.device_allocator,
            need,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );
        self.bg_color_staging_capacity = need;
    }

    const stage_slice = self.bg_color_staging.hostSlice(u8) orelse
        return error.MemoryMapFailed;
    @memcpy(stage_slice[0..need], colors[0..need]);

    try transitionImageLayout(
        &frame.main_cmd,
        self.bg_color_image.handle,
        self.bg_color_layout,
        .transfer_dst_optimal,
    );

    const copy_region = [_]vk.BufferImageCopy{.{
        .buffer_offset = 0,
        .buffer_row_length = 0,
        .buffer_image_height = 0,
        .image_offset = .{ .x = 0, .y = 0, .z = 0 },
        .image_extent = .{
            .width = cols,
            .height = rows,
            .depth = 1,
        },
        .image_subresource = .{
            .aspect_mask = .{ .color_bit = true },
            .mip_level = 0,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};

    try frame.main_cmd.copyBufferToImage(
        self.bg_color_staging.handle,
        self.bg_color_image.handle,
        .transfer_dst_optimal,
        &copy_region,
    );

    try transitionImageLayout(
        &frame.main_cmd,
        self.bg_color_image.handle,
        .transfer_dst_optimal,
        .shader_read_only_optimal,
    );

    self.bg_color_layout = .shader_read_only_optimal;
    self.bg_color_ready = true;
}

fn transitionImageLayout(
    cmd_buffer: *const core.CommandBuffer,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
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

    var arina = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arina.deinit();

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
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};

    try cmd_buffer.pipelineBarrierAuto(
        arina.allocator(),
        .{
            .src_stage_mask = src_stage_mask,
            .dst_stage_mask = dst_stage_mask,
            .image_barriers = &barriers,
        },
    );
}

const std = @import("std");
const vk = @import("vulkan");
const zerotty = @import("zerotty");

const core = @import("core/root.zig");
const platform = zerotty.system.platform;
const color = zerotty.terminal.color;
const font = zerotty.font;
const vertex = @import("../vertex.zig");

const root = @import("../root.zig");

const RenderContext = @import("rendering/RenderContext.zig");
const RenderPipeline = @import("rendering/RenderPipeline.zig");
const FrameManager = @import("rendering/FrameManager.zig");
const RenderTarget = @import("rendering/RenderTarget.zig");
const SwapchainTarget = @import("rendering/target/swapchain_target.zig").SwapchainTarget;

const Cache = @import("cache/Cache.zig");

comptime {
    _ = Cache;
    // _ = @import("vulkan/rendering/target/testing_target.zig");
    // _ = @import("vulkan/rendering/golden_sample.zig");
}

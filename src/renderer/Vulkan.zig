const Vulkan = @This();

pub const InitError = anyerror;

render_context: RenderContext,
render_pipeline: RenderPipeline,
frames: Frames,

swapchain: core.Swapchain,
targets: []Target,

cache: Cache,
staging_buffer: core.Buffer,

current_frame: ?*Frames.FrameResources,
current_image: u32,

bg_color: color.RGBA,

pub fn init(
    allocator: std.mem.Allocator,
    window_handles: win.WindowHandles,
    _: win.WindowRequirements,
    settings: root.RendererSettings,
) InitError!Vulkan {
    const render_context = try RenderContext.init(allocator, window_handles);

    const swapchain = try core.Swapchain.init(
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
    );

    const images_count = swapchain.images.len;

    const frames = try Frames.init(
        render_context.device,
        render_context.device_allocator,
        allocator,
        2,
        swapchain.images.len,
    );

    const render_pipeline = try RenderPipeline.init(
        allocator,
        render_context.device,
        .{
            .image_attachemnt_format = swapchain.surface_format.format,
            .extent = swapchain.extent,
        },
        .{ .descriptor_set_layouts = frames.descriptor_layouts },
    );

    const targets = try allocator.alloc(Target, images_count);

    for (0..images_count) |i| {
        targets[i] = Target.init(swapchain.image_views[i]);
    }

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

    return .{
        .render_context = render_context,
        .render_pipeline = render_pipeline,
        .swapchain = swapchain,
        .frames = frames,
        .targets = targets,
        .cache = cache,
        .staging_buffer = staging_buffer,
        .current_image = 0,
        .current_frame = null,
        .bg_color = .black,
    };
}

pub fn deinit(self: *Vulkan) void {
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;
    const device_allocator = self.render_context.device_allocator;

    const images_count = self.swapchain.images.len;

    device.waitIdle() catch {};

    for (0..images_count) |i| {
        self.targets[i].deinit(device);
    }
    allocator.free(self.targets);

    self.cache.deinit(allocator, device_allocator);
    self.frames.deinit(device, allocator);

    self.render_pipeline.deinit(device, allocator);
    self.swapchain.deinit(allocator);
    self.render_context.deinit();
}

pub fn beginFrame(self: *Vulkan) !void {
    const frame = self.frames.frameBegin(self.render_context.device, &self.swapchain) catch |err| blk: {
        if (err == error.OutOfDateKHR)
            try self.resizeSurface(0, 0);
        break :blk try self.frames.frameBegin(self.render_context.device, &self.swapchain);
    };
    self.current_frame = frame;

    const cmd = &frame.main_cmd;

    try cmd.begin(.{ .one_time_submit_bit = true });

    try frame.descriptor_sets[0].reset();
    try frame.descriptor_sets[0].addDescriptor(0, 0, .{
        .buffer = frame.uniform_buffer.getDescriptorBufferInfo(),
    });
    frame.descriptor_sets[0].update();

    try self.cache.updateDescriptorSet(&frame.descriptor_sets[1]);

    try cmd.bindPipeline(self.render_pipeline.pipeline.handle, .graphics);

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swapchain.extent.width),
        .height = @floatFromInt(self.swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    try cmd.setViewPort(&viewport);

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };
    try cmd.setScissor(&scissor);
}

pub fn endFrame(self: *Vulkan) !void {
    if (self.current_frame) |frame| {
        const staging_uniform_ptr = self.frames.uniform_stage
            .hostPtr(vertex.TextUniform) orelse unreachable;

        const screen_extent = self.swapchain.extent;

        const screen_w = @as(f32, @floatFromInt(screen_extent.width));
        const screen_h = @as(f32, @floatFromInt(screen_extent.height));

        const atlas_w: f32 = 2048;
        const atlas_h: f32 = 2048;

        const cell_w: f32 = 20.0;
        const cell_h: f32 = 20.0;

        staging_uniform_ptr.* = vertex.TextUniform{
            .screen_to_clip_scale = .from(2.0 / screen_w, 2.0 / screen_h),
            .screen_to_clip_offset = .from(-1.0, -1.0),
            .inv_atlas_size = .from(1.0 / atlas_w, 1.0 / atlas_h),
            .cell_size = .from(cell_w, cell_h),
            .baseline = 0,
        };

        var copy_cmd = try frame.command_pool.allocBuffer(.secondary);

        try copy_cmd.beginSecondary(
            null,
            null,
            0,
            .{ .one_time_submit_bit = true },
        );

        try copy_cmd.copyBuffer(
            self.frames.uniform_stage.handle,
            frame.uniform_buffer.handle,
            &.{
                .{
                    .src_offset = self.frames.uniform_stage.mem_alloc.?.offset,
                    .dst_offset = frame.uniform_buffer.mem_alloc.?.offset,
                    .size = @sizeOf(vertex.TextUniform),
                },
            },
        );

        try copy_cmd.end();

        try frame.main_cmd.executeCommand(copy_cmd.handle);

        for (0..2) |i| {
            try frame.descriptor_sets[i].prepare();
            frame.descriptor_sets[i].update();
        }

        if (frame.vertex_buffer.mem_alloc) |mem| {
            try frame.main_cmd.bindVertexBuffer(
                &frame.vertex_buffer,
                mem.offset,
            );

            for (0..2) |i|
                try frame.main_cmd.bindDescriptorSet(
                    &frame.descriptor_sets[i],
                    @intCast(i),
                    self.render_pipeline.pipeline_layout.handle,
                );

            const clear_values = [_]vk.ClearValue{
                .{ .color = .{ .float_32 = self.bg_color.floatArray() } },
            };

            const image_index = frame.image_index;
            const framebuffer = try self.targets[image_index].frameBuffer(
                &self.render_pipeline.renderpass,
                self.swapchain.extent,
            );

            try frame.main_cmd.beginRenderPass(
                &self.render_pipeline.renderpass,
                framebuffer,
                &clear_values,
                .@"inline",
            );

            const instance_count: u32 = @intCast(mem.size / @sizeOf(vertex.TextInstance));
            try frame.main_cmd.draw(6, instance_count, 0, 0);

            try frame.main_cmd.endRenderPass();
        }

        try frame.main_cmd.end();
    } else return error.FrameDidNotStart;

    self.current_frame = null;
}

pub fn presnt(self: *Vulkan) !void {
    const queue = self.render_context.queue;
    try self.frames.submit(&queue, null, &self.swapchain);
}

pub fn clear(self: *Vulkan, bg_color: color.RGBA) void {
    self.bg_color = bg_color;
}

pub fn setViewport(self: *Vulkan, x: u32, y: u32, width: u32, height: u32) !void {
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
        try frame.main_cmd.setViewPort(&viewport);
        try frame.main_cmd.setScissor(&scissor);
    }
}

pub fn resizeSurface(self: *Vulkan, width: u32, height: u32) !void {
    try self.render_context.device.waitIdle();

    const new_extent = try self.render_context.getSurfaceExtent(width, height);

    if (self.swapchain.extent.width == new_extent.width and
        self.swapchain.extent.height == new_extent.height)
    {
        return;
    }

    try self.swapchain.recreate(
        self.render_context.allocator_adapter.allocator,
        new_extent,
    );

    for (0..self.swapchain.images.len) |i| {
        self.targets[i].deinit(self.render_context.device);
        self.targets[i] = Target.init(self.swapchain.image_views[i]);
    }
}

pub fn cacheGlyphs(
    self: *Vulkan,
    entries: []font.GlyphAtlasEntry,
    bitmap_pool: []const u8,
) !void {
    const frame = self.current_frame orelse return error.FrameDidNotStart;

    if (self.staging_buffer.mem_alloc == null or
        self.staging_buffer.mem_alloc.?.size < bitmap_pool.len)
    {
        self.staging_buffer.deinit(self.render_context.device_allocator);
        self.staging_buffer = try .initAlloc(
            self.render_context.device_allocator,
            bitmap_pool.len,
            .{ .transfer_src_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );
    }

    const stage_slice = self.staging_buffer.hostSlice(u8) orelse
        return error.MemoryMapFailed;
    @memcpy(stage_slice[0..bitmap_pool.len], bitmap_pool);

    var copy_cmd = try frame.command_pool.allocBuffer(.secondary);
    try copy_cmd.beginSecondary(null, null, 0, .{ .one_time_submit_bit = true });
    try self.cache.recordCopyCmd(
        &copy_cmd,
        &self.staging_buffer,
        self.render_context.allocator_adapter.allocator,
        entries,
    );
    try copy_cmd.end();

    try frame.main_cmd.executeCommand(copy_cmd.handle);
}

pub fn reserveBatch(self: *Vulkan, count: usize) ![]vertex.TextInstance {
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

pub fn commitBatch(self: *Vulkan, count: usize) !void {
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
        var copy_cmd = try frame.command_pool.allocBuffer(.secondary);

        const copy_regons = [_]vk.BufferCopy{
            .{
                .src_offset = self.staging_buffer.mem_alloc.?.offset,
                .dst_offset = frame.vertex_buffer.mem_alloc.?.offset,
                .size = count * @sizeOf(vertex.TextInstance),
            },
        };

        try copy_cmd.beginSecondary(
            null,
            null,
            0,
            .{ .one_time_submit_bit = true },
        );

        try copy_cmd.copyBuffer(
            self.staging_buffer.handle,
            frame.vertex_buffer.handle,
            &copy_regons,
        );

        try copy_cmd.end();

        try frame.main_cmd.executeCommand(copy_cmd.handle);

        try frame.main_cmd.bindVertexBuffer(
            &frame.vertex_buffer,
            frame.vertex_buffer.mem_alloc.?.offset,
        );
    } else return error.FrameDidNotStart;
}

const std = @import("std");
const vk = @import("vulkan");

const root = @import("root.zig");

const core = @import("core");
const win = @import("window");
const color = @import("color");
const font = @import("font");
const vertex = @import("vertex.zig");

const RenderContext = @import("vulkan/rendering/RenderContext.zig");
const RenderPipeline = @import("vulkan/rendering/RenderPipeline.zig");
// const RenderResources = @import("vulkan/rendering/Resources.zig");
const Frames = @import("vulkan/rendering/Frames.zig");
const Target = @import("vulkan/rendering/Target.zig");

const Cache = @import("vulkan/cache/Cache.zig");

test Vulkan {
    std.testing.refAllDeclsRecursive(Cache);
}

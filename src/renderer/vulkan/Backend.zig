const Backend = @This();

render_context: RenderContext,
render_pipeline: RenderPipeline,
render_resources: RenderResources,

swapchain: core.Swapchain,
render_targets: []core.RenderTarget,
framebuffers: []core.Framebuffer,

window_height: u32,
window_width: u32,

// Frame synchronization
current_frame: u32,
max_frames_in_flight: u32,
in_flight_fences: []vk.Fence,
image_available_semaphores: []vk.Semaphore,
render_finished_semaphores: []vk.Semaphore,

// Command management
command_pool: core.CommandPool,
command_buffers: []core.CommandBuffer,

atlas: Atlas,
grid: Grid,

copy_command_buffer: core.CommandBuffer,
copy_fence: vk.Fence,

pub const log = std.log.scoped(.renderer);

pub fn init(window: *Window, allocator: Allocator, grid_rows: u32, grid_cols: u32) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator, grid_rows, grid_cols);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator, grid_rows: u32, grid_cols: u32) !void {
    self.atlas = try Atlas.create(allocator, 20, 20, 0, 128);
    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    self.render_context = try RenderContext.init(allocator, window);
    const device = self.render_context.device;

    // Initialize swapchain
    self.swapchain = try core.Swapchain.init(self.render_context.instance, device, allocator, self.render_context.surface, .{
        .extent = .{ .height = window.height, .width = window.width },
    });

    self.render_targets = try core.RenderTarget.initFromSwapchain(&self.swapchain, allocator);

    // Initialize resources
    const max_cells = grid_rows * grid_cols;

    self.render_resources = try RenderResources.init(
        allocator,
        device,
        self.render_context.device_allocator,
        max_cells,
        256,
        @intCast(self.atlas.width),
        @intCast(self.atlas.height),
    );

    // Update descriptor sets after initialization
    try self.render_resources.updateDescriptorSet();

    // Initialize render pipeline
    self.render_pipeline = try RenderPipeline.init(
        allocator,
        device,
        .{
            .image_attachemnt_format = self.swapchain.surface_format.format,
            .extent = self.swapchain.extent,
        },
        .{ .descriptor_set_layouts = &.{self.render_resources.layout} },
    );

    // Create framebuffers
    self.framebuffers = try allocator.alloc(core.Framebuffer, self.render_targets.len);
    errdefer allocator.free(self.framebuffers);

    for (0..self.render_targets.len) |i| {
        self.framebuffers[i] = try core.Framebuffer.init(device, &self.render_pipeline.renderpass, &self.render_targets[i]);
    }

    // Setup frame synchronization
    self.max_frames_in_flight = @min(self.swapchain.images.len, 3);
    self.current_frame = 0;

    self.in_flight_fences = try allocator.alloc(vk.Fence, self.max_frames_in_flight);
    self.image_available_semaphores = try allocator.alloc(vk.Semaphore, self.max_frames_in_flight);
    self.render_finished_semaphores = try allocator.alloc(vk.Semaphore, self.max_frames_in_flight);

    for (0..self.max_frames_in_flight) |i| {
        self.in_flight_fences[i] = try device.createFence(true);
        self.image_available_semaphores[i] = try device.createSemaphore();
        self.render_finished_semaphores[i] = try device.createSemaphore();
    }

    self.copy_fence = try device.createFence(false);

    // Setup command pool and buffers
    self.command_pool = try core.CommandPool.init(device, device.physical_device.graphic_family_index);
    self.command_buffers = try self.command_pool.allocBuffers(allocator, .primary, self.max_frames_in_flight);

    self.copy_command_buffer = try self.command_pool.allocBuffer(.primary);

    // Store window dimensions
    self.window_width = window.width;
    self.window_height = window.height;

    try self.render_resources.uploadFontAtlas(
        &self.copy_command_buffer,
        &self.render_context.queue,
        self.copy_fence,
        self.render_context.device_allocator,
        self.atlas.buffer,
        @intCast(self.atlas.height),
        @intCast(self.atlas.width),
    );
}

pub fn deinit(self: *Backend) void {
    const instance = self.render_context.instance;
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;

    // Wait for device to finish operations
    _ = device.vkd.deviceWaitIdle(device.handle) catch {};

    // Clean up synchronization objects
    for (0..self.max_frames_in_flight) |i| {
        device.vkd.destroyFence(device.handle, self.in_flight_fences[i], device.vk_allocator);
        device.vkd.destroySemaphore(device.handle, self.image_available_semaphores[i], device.vk_allocator);
        device.vkd.destroySemaphore(device.handle, self.render_finished_semaphores[i], device.vk_allocator);
    }
    allocator.free(self.in_flight_fences);
    allocator.free(self.image_available_semaphores);
    allocator.free(self.render_finished_semaphores);

    device.vkd.destroyFence(device.handle, self.copy_fence, device.vk_allocator);

    // Clean up framebuffers
    for (self.framebuffers) |framebuffer| {
        device.vkd.destroyFramebuffer(device.handle, framebuffer.handle, device.vk_allocator);
    }
    allocator.free(self.framebuffers);

    // Clean up command pool and buffers
    self.command_pool.deinit();
    allocator.free(self.command_buffers);

    // Clean up resources
    self.render_resources.deinit(device, self.render_context.device_allocator, allocator);

    // Clean up pipeline
    self.render_pipeline.deinit(device, allocator);

    // Clean up swapchain
    self.swapchain.deinit(allocator);

    // Clean up surface
    instance.vki.destroySurfaceKHR(instance.handle, self.swapchain.surface, instance.vk_allocator);

    // Clean up render targets
    for (self.render_targets) |target| {
        target.deinit(device, allocator);
    }
    allocator.free(self.render_targets);

    self.render_context.deinit();

    self.atlas.deinit(allocator);
    self.grid.free(allocator);
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    // Note: Clear color is now handled in renderGrid()
    // This function can be used to store the clear color for future use
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;

    _ = device.vkd.deviceWaitIdle(device.handle) catch {};

    for (self.framebuffers) |framebuffer| {
        device.vkd.destroyFramebuffer(device.handle, framebuffer.handle, device.vk_allocator);
    }
    // allocator.free(self.framebuffers);

    for (self.render_targets) |target| {
        target.deinit(device, allocator);
    }
    allocator.free(self.render_targets);

    try self.swapchain.recreate(allocator, .{ .width = width, .height = height });

    self.render_targets = try core.RenderTarget.initFromSwapchain(&self.swapchain, allocator);

    // self.framebuffers = try allocator.alloc(core.Framebuffer, self.render_targets.len);
    for (0..self.render_targets.len) |i| {
        self.framebuffers[i] = try core.Framebuffer.init(device, &self.render_pipeline.renderpass, &self.render_targets[i]);
    }
}

pub fn presentBuffer(self: *Backend) void {
    // Present functionality is now integrated into renderGrid()
    // This function can be used as a wrapper if needed
    _ = self;
}

pub fn renaderGrid(self: *Backend) !void {
    const device = self.render_context.device;

    // Wait for previous frame to finish
    _ = try device.vkd.waitForFences(
        device.handle,
        1,
        &.{self.in_flight_fences[self.current_frame]},
        vk.Bool32.true,
        std.math.maxInt(u64),
    );

    // Acquire next image from swapchain
    const acquire_result = device.vkd.acquireNextImageKHR(
        device.handle,
        self.swapchain.handle,
        std.math.maxInt(u64),
        self.image_available_semaphores[self.current_frame],
        .null_handle,
    );

    const image_index = blk: {
        const result = acquire_result catch |err| switch (err) {
            error.OutOfDateKHR => {
                // Swapchain needs recreation, for now just skip frame
                return;
            },
            else => return err,
        };
        break :blk result.image_index;
    };

    // Reset fence for this frame
    _ = device.vkd.resetFences(device.handle, 1, &.{self.in_flight_fences[self.current_frame]}) catch {};

    // Reset and begin command buffer
    try self.command_buffers[self.current_frame].reset(false);
    try self.command_buffers[self.current_frame].begin(.{});

    try self.command_buffers[self.current_frame].beginRenderPass(
        &self.render_pipeline.renderpass,
        self.framebuffers[image_index],
        null,
        .@"inline",
    );

    // Bind pipeline
    self.command_buffers[self.current_frame].bindPipeline(self.render_pipeline.pipeline.handle, .graphics) catch {};

    // Bind vertex buffer and descriptor sets
    // TODO: Implement proper binding
    try self.render_resources.bindVertexBuffers(&self.command_buffers[self.current_frame]);

    try self.render_resources.bindResources(
        &self.command_buffers[self.current_frame],
        self.render_pipeline.pipeline_layout.handle,
    );

    // Set viewport and scissor (required since they are dynamic states)
    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swapchain.extent.width),
        .height = @floatFromInt(self.swapchain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };
    try self.command_buffers[self.current_frame].setViewPort(&viewport);
    try self.command_buffers[self.current_frame].setScissor(&scissor);

    // Draw call (instanced rendering for terminal cells)
    // For now, skip draw call - TODO: Implement
    // const cell_count: u32 = 1; // TODO: Get actual cell count from grid
    try self.command_buffers[self.current_frame].draw(6, 1, 0, 0);
    // TODO: Implement draw call

    // End render pass
    try self.command_buffers[self.current_frame].endRenderPass();

    // End command buffer
    try self.command_buffers[self.current_frame].end();

    // Submit command buffer
    try self.render_context.queue.submitOne(
        &self.command_buffers[self.current_frame],
        self.image_available_semaphores[self.current_frame],
        self.render_finished_semaphores[self.current_frame],
        .{ .color_attachment_output_bit = true },
        self.in_flight_fences[self.current_frame],
    );

    // Present to screen
    _ = try self.render_context.queue.presentOne(
        &self.swapchain,
        self.render_finished_semaphores[self.current_frame],
        image_index,
    );

    // Advance to next frame
    self.current_frame = (self.current_frame + 1) % self.max_frames_in_flight;
}

pub fn setCell(
    self: *Backend,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    const cell_index = row * self.grid.cols + col;
    if (cell_index >= self.render_resources.max_cells) return error.OutOfRange;

    const cell_instance = vertex.Instance{
        .packed_pos = .{ .row = @intCast(row), .col = @intCast(col) },
        .glyph_index = char_code,
        .style_index = 0,
    };

    const cell_style = vertex.GlyphStyle{
        .fg_color = fg_color orelse ColorRGBAu8{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .bg_color = bg_color orelse ColorRGBAu8{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };

    try self.render_resources.updateCellData(&.{cell_instance});
    try self.render_resources.updateStyleData(&.{cell_style});
}

const std = @import("std");
const builtin = @import("builtin");
const assets = @import("assets");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");

const core = @import("core/root.zig");

const Window = @import("../../window/root.zig").Window;
const RenderContext = @import("rendering/RenderContext.zig");
const RenderPipeline = @import("rendering/RenderPipeline.zig");
const RenderResources = @import("rendering/Resources.zig");
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("../common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("../common/color.zig").ColorRGBAf32;
// const DynamicLibrary = @import("../../DynamicLibrary.zig");
const Grid = @import("../../Grid.zig");
const Atlas = @import("../../font/Atlas.zig");

const vertex = @import("rendering/vertex.zig");

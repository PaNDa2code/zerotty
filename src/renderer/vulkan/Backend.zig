const Backend = @This();

render_context: RenderContext,
render_pipeline: RenderPipeline,
render_resources: RenderResources,

swapchain: core.Swapchain,
render_targets: []core.RenderTarget,

window_height: u32,
window_width: u32,

pub const log = std.log.scoped(.renderer);

pub fn init(window: *Window, allocator: Allocator) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator) !void {
    self.render_context = try RenderContext.init(allocator, window);

    const device = self.render_context.device;
    const surface = self.render_context.surface;

    const present_queue = core.Queue.init(
        device,
        0,
        device.physical_device.present_family_index,
        device.physical_device.support_present,
    );

    const graphics_queue = core.Queue.init(
        device,
        0,
        device.physical_device.graphic_family_index,
        false,
    );

    _ = graphics_queue;
    _ = present_queue;

    self.swapchain =
        try core.Swapchain.init(self.render_context.instance, self.render_context.device, allocator, surface, .{
            .extent = .{
                .height = window.height,
                .width = window.width,
            },
        });

    self.render_targets = try core.RenderTarget.initFromSwapchain(&self.swapchain, allocator);

    self.render_resources = try RenderResources.init(allocator, device, self.render_context.device_allocator, 1000, 1000, 1000, 1000);

    self.render_pipeline = try RenderPipeline.init(
        allocator,
        self.render_context.device,
        .{
            .extent = self.swapchain.extent,
            .image_attachemnt_format = self.swapchain.surface_format.format,
        },
        .{ .descriptor_set_layouts = &.{self.render_resources.descriptor_layout} },
    );

    const framebuffers = try allocator.alloc(core.Framebuffer, self.render_targets.len);
    defer {
        for (framebuffers) |framebuffer| {
            device.vkd.destroyFramebuffer(
                device.handle,
                framebuffer.handle,
                device.vk_allocator,
            );
        }
        allocator.free(framebuffers);
    }

    for (0..framebuffers.len) |i| {
        framebuffers[i] = try core.Framebuffer.init(self.render_context.device, &self.render_pipeline.renderpass, &self.render_targets[i]);
    }


    const cmd_pool = try core.CommandPool.init(
        device,
        device.physical_device.graphic_family_index,
    );
    defer cmd_pool.deinit();

    var sec_cmd_buffer = try cmd_pool.allocBuffer(.secondary);
    try sec_cmd_buffer.reset(false);
    try sec_cmd_buffer.beginSecondary(null, null, 0, .{});
    try sec_cmd_buffer.end();
    var cmd_buffer = try cmd_pool.allocBuffer(.primary);
    try cmd_buffer.begin(.{});
    try cmd_buffer.executeCommand(sec_cmd_buffer.handle);
    try cmd_buffer.beginRenderPass(&self.render_pipeline.renderpass, framebuffers[0], null, .secondary_command_buffers);
    try cmd_buffer.endRenderPass();
    try cmd_buffer.end();

    const vram_allocator = self.render_context.device_allocator;

    var image_builder = core.Image.Builder.new();

    const image = try image_builder
        .setFormat(.r8_unorm)
        .setSize(100, 100)
        .asTexture()
        .build(vram_allocator);
    defer image.deinit(vram_allocator);

    var vertex_buffer = try core.Buffer.initAlloc(
        vram_allocator,
        1024,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
        .{ .device_local_bit = true, .host_visible_bit = true },
        .exclusive,
    );
    defer vertex_buffer.deinit(vram_allocator);

    const vertex_buffer_descriptor_info = vertex_buffer.getDescriptorBufferInfo();

    const buffer_infos = try allocator.alloc([]vk.DescriptorBufferInfo, 1);
    defer allocator.free(buffer_infos);
    buffer_infos[0] = try allocator.alloc(vk.DescriptorBufferInfo, 1);
    defer allocator.free(buffer_infos[0]);

    buffer_infos[0][0] = vertex_buffer_descriptor_info;
}

pub fn deinit(self: *Backend) void {
    const instance = self.render_context.instance;
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;

    self.swapchain.deinit(allocator);

    instance.vki.destroySurfaceKHR(
        instance.handle,
        self.swapchain.surface,
        instance.vk_allocator,
    );

    self.render_pipeline.renderpass.deinit(allocator);

    for (self.render_targets) |target| {
        target.deinit(device, self.render_context.allocator_adapter.allocator);
    }
    self.render_context.allocator_adapter.allocator.free(self.render_targets);

    self.render_context.deinit();
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    try self.swapchain.recreate(
        self.render_context.allocator_adapter.allocator,
        .{ .width = width, .height = height },
    );

    for (self.render_targets) |target| {
        target.deinit(self.render_context.device, self.render_context.allocator_adapter.allocator);
    }
    self.render_context.allocator_adapter.allocator.free(self.render_targets);

    self.render_targets = try core.RenderTarget.initFromSwapchain(
        &self.swapchain,
        self.render_context.allocator_adapter.allocator,
    );
}

pub fn presentBuffer(self: *Backend) void {
    _ = self;
}

pub fn renaderGrid(self: *Backend) void {
    _ = self;
}

pub fn setCell(
    self: *Backend,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    _ = bg_color; // autofix
    _ = fg_color; // autofix
    _ = char_code; // autofix
    _ = col; // autofix
    _ = row; // autofix
    _ = self; // autofix

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
// const Grid = @import("../../Grid.zig");
// const Atlas = @import("../../font/Atlas.zig");

const vertex_input = core.Pipeline.VertexInputDescriptionBuilder
    .addBinding(.{ .binding = 0, .stride = 0, .input_rate = .instance })
    .addAttribute(.{ .location = 1, .binding = 0, .format = .r32_uint, .offset = 0 })
    .addAttribute(.{ .location = 2, .binding = 0, .format = .r32_uint, .offset = 0 })
    .addAttribute(.{ .location = 3, .binding = 0, .format = .r32_uint, .offset = 0 })
    .collect();

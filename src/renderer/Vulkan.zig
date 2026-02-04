const Vulkan = @This();

pub const InitError = anyerror;

render_context: RenderContext,
render_pipeline: RenderPipeline,
// render_resources: RenderResources,
frames: Frames,

swapchain: core.Swapchain,
targets: []Target,

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
        .{ .descriptor_set_layouts = &.{frames.descriptor_layout} },
    );

    const targets = try allocator.alloc(Target, images_count);

    for (0..images_count) |i| {
        targets[i] = Target.init(swapchain.image_views[i]);
    }

    return .{
        .render_context = render_context,
        .render_pipeline = render_pipeline,
        .swapchain = swapchain,
        .frames = frames,
        .targets = targets,
        .current_image = 0,
        .current_frame = null,
        .bg_color = .black,
    };
}

pub fn deinit(self: *Vulkan) void {
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;
    // const device_allocator = self.render_context.device_allocator;

    const images_count = self.swapchain.images.len;

    device.waitIdle() catch {};

    for (0..images_count) |i| {
        self.targets[i].deinit(device);
    }
    allocator.free(self.targets);

    self.frames.deinit(device, allocator);

    self.render_pipeline.deinit(device, allocator);
    self.swapchain.deinit(allocator);
    self.render_context.deinit();
}

pub fn beginFrame(self: *Vulkan) !void {
    const frame = try self.frames.frameBegin(self.render_context.device, &self.swapchain);
    self.current_frame = frame;

    const cmd = &frame.main_cmd;
    const image_index = frame.image_index;

    try cmd.begin(.{ .one_time_submit_bit = true });

    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = self.bg_color.floatArray() } },
    };

    const framebuffer = try self.targets[image_index].frameBuffer(
        &self.render_pipeline.renderpass,
        self.swapchain.extent,
    );

    try cmd.beginRenderPass(
        &self.render_pipeline.renderpass,
        framebuffer,
        &clear_values,
        .@"inline",
    );
}

pub fn endFrame(self: *Vulkan) !void {
    if (self.current_frame) |frame| {
        try frame.main_cmd.endRenderPass();
        try frame.main_cmd.end();
    } else return error.FrameDidNotStart;

    try self.frames.endFrame();

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

    if (self.current_frame) |frame| {
        try frame.main_cmd.setViewPort(&viewport);
    }
}

const std = @import("std");
const vk = @import("vulkan");

const root = @import("root.zig");

const core = @import("core");
const win = @import("window");
const color = @import("color");

const RenderContext = @import("vulkan/rendering/RenderContext.zig");
const RenderPipeline = @import("vulkan/rendering/RenderPipeline.zig");
// const RenderResources = @import("vulkan/rendering/Resources.zig");
const Frames = @import("vulkan/rendering/Frames.zig");
const Target = @import("vulkan/rendering/Target.zig");

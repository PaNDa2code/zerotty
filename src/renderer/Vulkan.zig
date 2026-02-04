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
) InitError!*Vulkan {
    const self = try allocator.create(Vulkan);

    self.render_context = try RenderContext.init(allocator, window_handles);

    self.swapchain = try core.Swapchain.init(
        self.render_context.instance,
        self.render_context.device,
        allocator,
        self.render_context.surface,
        .{
            .image_count = 2,
            .extent = .{
                .height = settings.surface_height,
                .width = settings.surface_width,
            },
        },
    );

    const images_count = self.swapchain.images.len;

    self.frames = try Frames.init(
        self.render_context.device,
        allocator,
        2,
        self.swapchain.images.len,
    );

    self.render_pipeline = try RenderPipeline.init(
        allocator,
        self.render_context.device,
        .{
            .image_attachemnt_format = self.swapchain.surface_format.format,
            .extent = self.swapchain.extent,
        },
        .{ .descriptor_set_layouts = &.{self.frames.descriptor_layout} },
    );

    self.targets = try allocator.alloc(Target, images_count);

    for (0..images_count) |i| {
        self.targets[i] = Target.init(self.swapchain.image_views[i]);
    }

    return self;
}

pub fn deinit(self: *Vulkan) void {
    const device = self.render_context.device;
    const allocator = self.render_context.allocator_adapter.allocator;
    // const device_allocator = self.render_context.device_allocator;

    self.render_pipeline.deinit(device, allocator);
    self.render_context.deinit();
}

pub fn beginFrame(self: *Vulkan) !void {
    self.current_frame = try self.frames.frameBegin(self.render_context.device, &self.swapchain);
    const cmd = &self.current_frame.?.main_cmd;
    const image_index = self.current_frame.?.image_index;

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
    try self.current_frame.?.main_cmd.end();
    try self.frames.endFrame();
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

    try self.current_frame.?.main_cmd.setViewPort(&viewport);
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

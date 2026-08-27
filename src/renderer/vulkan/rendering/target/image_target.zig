const std = @import("std");
const vk = @import("vulkan");

const core = @import("../../core/root.zig");

const RenderTarget = @import("../RenderTarget.zig");
const FrameInfo = RenderTarget.FrameInfo;
const PresentParams = RenderTarget.PresentParams;

pub const ImageTarget = struct {
    device: *const core.Device,
    device_allocator: *core.memory.DeviceAllocator,

    image: core.Image,

    framebuffer: core.Framebuffer,
    render_pass: core.RenderPass,

    extent: vk.Extent2D,
    format: vk.Format,

    pub const Options = struct {
        extent: vk.Extent2D = .{ .width = 800, .height = 600 },
        format: vk.Format = .b8g8r8a8_srgb,
    };

    pub const InitError = core.Image.Builder.BuildError ||
        core.RenderPass.InitError ||
        core.Framebuffer.InitError ||
        std.mem.Allocator.Error;

    pub fn init(
        device: *const core.Device,
        device_allocator: *core.memory.DeviceAllocator,
        allocator: std.mem.Allocator,
        options: Options,
    ) InitError!ImageTarget {
        const image = try core.Image.Builder.new()
            .setSize(options.extent.width, options.extent.height)
            .setFormat(options.format)
            .setUsage(.{ .color_attachment_bit = true, .sampled_bit = true })
            .build(device_allocator);

        errdefer image.deinit(device_allocator);

        const render_pass = try createRenderPass(device, allocator, options.format);
        errdefer render_pass.deinit(allocator);

        const framebuffer = try core.Framebuffer.init(
            device,
            &render_pass,
            &.{image.view},
            options.extent,
        );

        return .{
            .device = device,
            .device_allocator = device_allocator,
            .image = image,
            .framebuffer = framebuffer,
            .render_pass = render_pass,
            .extent = options.extent,
            .format = options.format,
        };
    }

    pub fn deinit(self: *ImageTarget, allocator: std.mem.Allocator) void {
        self.framebuffer.deinit(self.device);
        self.render_pass.deinit(allocator);
        self.image.deinit(self.device_allocator);
    }

    pub fn acquireFrameFn(ptr: *anyopaque, _: vk.Fence) RenderTarget.Error!FrameInfo {
        const self: *ImageTarget = @ptrCast(@alignCast(ptr));

        return .{
            .image_index = 0,
            .image_ready = .null_handle,
            .framebuffer = self.framebuffer,
            .extent = self.extent,
            .format = self.format,
        };
    }

    pub fn presentFrameFn(ptr: *anyopaque, params: PresentParams) RenderTarget.Error!void {
        const self: *ImageTarget = @ptrCast(@alignCast(ptr));
        _ = self;

        params.queue.submitOne(
            params.cmd,
            .null_handle,
            .null_handle,
            .{ .color_attachment_output_bit = true },
            params.in_flight_fence,
        ) catch return error.QueueCannotPresnt;
    }

    pub fn getExtentFn(ptr: *anyopaque) vk.Extent2D {
        const self: *ImageTarget = @ptrCast(@alignCast(ptr));
        return self.extent;
    }

    pub fn getFinalLayoutFn(_: *anyopaque) vk.ImageLayout {
        return .shader_read_only_optimal;
    }

    pub fn deinitFn(ptr: *anyopaque) void {
        const self: *ImageTarget = @ptrCast(@alignCast(ptr));
        self.deinit(std.heap.page_allocator);
    }

    pub fn interface(self: *ImageTarget) RenderTarget {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub const vtable = RenderTarget.VTable{
        .acquireFrame = acquireFrameFn,
        .presentFrame = presentFrameFn,
        .getExtent = getExtentFn,
        .getFinalLayout = getFinalLayoutFn,
        .deinit = deinitFn,
    };

    fn createRenderPass(
        device: *const core.Device,
        allocator: std.mem.Allocator,
        format: vk.Format,
    ) !core.RenderPass {
        var builder = core.RenderPass.Builder.init(allocator);
        defer builder.deinit();

        try builder.addAttachment(.{
            .format = format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .shader_read_only_optimal,
        });

        try builder.addSubpass(.{
            .pipeline_bind_point = .graphics,
            .color_attachments = &.{
                .{ .attachment = 0, .layout = .color_attachment_optimal },
            },
        });

        try builder.addDependency(.{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true },
        });

        return builder.build(device);
    }
};

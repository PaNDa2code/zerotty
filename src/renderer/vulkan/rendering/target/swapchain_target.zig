const std = @import("std");
const vk = @import("vulkan");

const core = @import("../../core/root.zig");

const RenderTarget = @import("../RenderTarget.zig");
const FrameInfo = RenderTarget.FrameInfo;
const PresentParams = RenderTarget.PresentParams;

pub const SwapchainTarget = struct {
    device: *const core.Device,
    allocator: std.mem.Allocator,
    swapchain: core.Swapchain,

    framebuffers: []core.Framebuffer,

    image_available: []vk.Semaphore,
    render_finished: []vk.Semaphore,
    images_in_flight: []vk.Fence,

    current_frame: usize = 0,
    current_image_index: u32 = 0,

    pub const InitError = core.Swapchain.InitError ||
        std.mem.Allocator.Error ||
        core.Device.CreateSemaphoreError;

    pub fn init(
        instance: *const core.Instance,
        device: *const core.Device,
        allocator: std.mem.Allocator,
        surface: vk.SurfaceKHR,
        options: core.Swapchain.SwapchainOptions,
        max_frames_in_flight: u32,
    ) InitError!SwapchainTarget {
        const swapchain = try core.Swapchain.init(
            instance,
            device,
            allocator,
            surface,
            options,
        );

        const image_count = swapchain.images.len;

        const image_available = try allocator.alloc(vk.Semaphore, max_frames_in_flight);
        for (0..max_frames_in_flight) |i| {
            image_available[i] = try device.createSemaphore();
        }

        const render_finished = try allocator.alloc(vk.Semaphore, image_count);
        for (0..image_count) |i| {
            render_finished[i] = try device.createSemaphore();
        }

        const images_in_flight = try allocator.alloc(vk.Fence, image_count);
        @memset(images_in_flight, .null_handle);

        const framebuffers = try allocator.alloc(core.Framebuffer, image_count);
        @memset(framebuffers, .{ .handle = .null_handle, .extent = undefined });

        return .{
            .device = device,
            .allocator = allocator,
            .swapchain = swapchain,
            .framebuffers = framebuffers,
            .image_available = image_available,
            .render_finished = render_finished,
            .images_in_flight = images_in_flight,
        };
    }

    pub fn deinit(self: *SwapchainTarget, allocator: std.mem.Allocator) void {
        for (self.image_available) |sem| {
            self.device.destroySemaphore(sem);
        }
        for (self.render_finished) |sem| {
            self.device.destroySemaphore(sem);
        }
        for (self.framebuffers) |fb| {
            fb.deinit(self.device);
        }

        allocator.free(self.image_available);
        allocator.free(self.render_finished);
        allocator.free(self.images_in_flight);
        allocator.free(self.framebuffers);

        self.swapchain.deinit(allocator);
    }

    pub fn ensureFramebuffers(
        self: *SwapchainTarget,
        render_pass: *const core.RenderPass,
    ) !void {
        for (0..self.swapchain.image_views.len) |i| {
            if (self.framebuffers[i].handle == .null_handle) {
                self.framebuffers[i] = try core.Framebuffer.init(
                    self.device,
                    render_pass,
                    &.{self.swapchain.image_views[i]},
                    self.swapchain.extent,
                );
            }
        }
    }

    pub fn recreate(
        self: *SwapchainTarget,
        allocator: std.mem.Allocator,
        extent: vk.Extent2D,
    ) !void {
        for (self.framebuffers) |fb| {
            fb.deinit(self.device);
        }

        try self.swapchain.recreate(allocator, extent);

        for (self.framebuffers) |*fb| {
            fb.* = .{ .handle = .null_handle, .extent = undefined };
        }
    }

    pub fn getFramebuffer(self: *SwapchainTarget, image_index: u32) core.Framebuffer {
        return self.framebuffers[image_index];
    }

    pub fn getRenderPass(self: *SwapchainTarget) core.Swapchain {
        return self.swapchain;
    }

    pub fn acquireFrameFn(ptr: *anyopaque, in_flight_fence: vk.Fence) RenderTarget.Error!FrameInfo {
        const self: *SwapchainTarget = @ptrCast(@alignCast(ptr));

        const image_available = self.image_available[self.current_frame];

        const acquire_result = self.swapchain.acquireNextImage(
            std.math.maxInt(u64),
            image_available,
            .null_handle,
        ) catch return error.TargetNotReady;

        const image_index = switch (acquire_result) {
            .success, .suboptimal_khr => |index| index,
            else => return error.TargetNotReady,
        };

        const image_fence = self.images_in_flight[image_index];
        if (image_fence != .null_handle and
            image_fence != in_flight_fence)
        {
            _ = self.device.waitFence(image_fence, std.math.maxInt(u64)) catch {};
        }
        self.images_in_flight[image_index] = in_flight_fence;

        self.current_image_index = image_index;

        return .{
            .image_index = image_index,
            .image_ready = image_available,
            .framebuffer = self.framebuffers[image_index],
            .extent = self.swapchain.extent,
            .format = self.swapchain.surface_format.format,
        };
    }

    pub fn presentFrameFn(ptr: *anyopaque, params: PresentParams) RenderTarget.Error!void {
        const self: *SwapchainTarget = @ptrCast(@alignCast(ptr));

        const image_available = self.image_available[self.current_frame];
        const render_finished = self.render_finished[self.current_image_index];

        params.queue.submitOne(
            params.cmd,
            image_available,
            render_finished,
            .{ .color_attachment_output_bit = true },
            params.in_flight_fence,
        ) catch return error.QueueCannotPresnt;

        _ = params.queue.presentOne(
            &self.swapchain,
            render_finished,
            self.current_image_index,
        ) catch return error.QueueCannotPresnt;

        self.current_frame = (self.current_frame + 1) % self.image_available.len;
    }

    pub fn getExtentFn(ptr: *anyopaque) vk.Extent2D {
        const self: *SwapchainTarget = @ptrCast(@alignCast(ptr));
        return self.swapchain.extent;
    }

    pub fn getFinalLayoutFn(_: *anyopaque) vk.ImageLayout {
        return .present_src_khr;
    }

    pub fn deinitFn(ptr: *anyopaque) void {
        const self: *SwapchainTarget = @ptrCast(@alignCast(ptr));
        self.deinit(self.allocator);
    }

    pub fn interface(self: *SwapchainTarget) RenderTarget {
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
};

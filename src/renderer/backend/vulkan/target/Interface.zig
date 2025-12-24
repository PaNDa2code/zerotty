//! handle the internal implmention of render presention (swapchain, headless).
const PresentTarget = @This();

const std = @import("std");
const vk = @import("vulkan");

pub const VTable = struct {
    create: *const fn (std.mem.Allocator, *const Context, *const anyopaque) anyerror!*anyopaque,
    destroy: *const fn (*anyopaque, std.mem.Allocator) void,

    acquire: *const fn (*anyopaque) anyerror!FrameImage,
    present: *const fn (*anyopaque, FrameImage) anyerror!void,

    resize: *const fn (*anyopaque, vk.Extent2D) anyerror!void,

    getExtent: *const fn (*anyopaque) vk.Extent2D,
    getFormat: *const fn (*anyopaque) vk.Format,
};

pub const FrameImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    index: u32,

    in_flight: vk.Fence,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
};

pub const WsiSurface = struct {
    handle: vk.SurfaceKHR,
    extent: vk.Extent2D,

    pub fn create(
        instance: Context.Instance,
        window: anytype,
    ) !WsiSurface {
        const handle = try WSI.createWindowSurface(
            &instance.vki,
            instance.handle,
            window,
            instance.vk_allocator,
        );

        return .{
            .handle = handle,
            .extent = .{
                .height = window.height,
                .width = window.width,
            },
        };
    }
};

ptr: *anyopaque,
vtable: VTable,

pub fn initWsi(
    allocator: std.mem.Allocator,
    context: *const Context,
    surface: WsiSurface,
) !WsiSurface {
    const vtable = wsi_vtable;
    const ptr = try vtable.create(allocator, context, &surface);
    return .{
        .ptr = ptr,
        .vtable = vtable,
    };
}

pub fn initHeadless(
    allocator: std.mem.Allocator,
    context: *const Context,
) !PresentTarget {
    const vtable = headless_vtable;
    const ptr = try vtable.create(allocator, context, null);
    return .{
        .ptr = ptr,
        .vtable = vtable,
    };
}

pub fn acquire(self: *const PresentTarget) !FrameImage {
    return self.vtable.acquire(self.ptr);
}

pub fn present(self: *const PresentTarget, frame_image: FrameImage) !void {
    try self.vtable.present(self.ptr, frame_image);
}

pub fn resize(self: *const PresentTarget, extent: vk.Extent2D) !void {
    const old_extent = self.getExtent();

    if (old_extent.height != extent.height or
        old_extent.width != extent.width)
    {
        try self.vtable.resize(self.ptr, extent);
    }
}

pub fn getExtent(self: *const PresentTarget) vk.Extent2D {
    return self.vtable.getExtent(self.ptr);
}

const Context = @import("../core/Context.zig");

const WSI = @import("WSI.zig");
const wsi_vtable = WSI.vtable;
const headless_vtable = @import("Headless.zig").vtable;

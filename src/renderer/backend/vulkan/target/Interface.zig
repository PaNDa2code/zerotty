//! handle the internal implmention of render presention (swapchain, headless).
const PresentTarget = @This();

const std = @import("std");
const vk = @import("vulkan");

pub const VTable = struct {
    create: *const fn (std.mem.Allocator, *const Context, ?*anyopaque) anyerror!*anyopaque,
    destroy: *const fn (*anyopaque, std.mem.Allocator) void,

    acquire: *const fn (*anyopaque) anyerror!FrameImage,
    present: *const fn (*anyopaque, FrameImage) anyerror!void,

    resize: *const fn (*anyopaque, vk.Extent2D) anyerror!void,

    getExtent: *const fn (*anyopaque) vk.Extent2D,
    getFormat: *const fn (*anyopaque) vk.Format,
};

pub const PresentMode = enum {
    VSync,
    Immediate,
    Mailbox,
    Relaxed,
};

pub const FrameImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    index: u32,
};

ptr: *anyopaque,
vtable: VTable,

pub fn createWsiSurface(
    allocator: std.mem.Allocator,
    context: *const Context,
    window: anytype,
) !PresentTarget {
    const vtable = swapchain_vtable;
    const ptr = try vtable.create(allocator, context, window);
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
const swapchain_vtable = @import("Swapchain.zig").vtable;
const headless_vtable = @import("Headless.zig").vtable;

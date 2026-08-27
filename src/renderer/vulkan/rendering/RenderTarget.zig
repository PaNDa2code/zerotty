const RenderTarget = @This();

const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");

ptr: *anyopaque,
vtable: *const VTable,

pub const FrameInfo = struct {
    image_index: u32,
    image_ready: vk.Semaphore,
    framebuffer: core.Framebuffer,
    extent: vk.Extent2D,
    format: vk.Format,
};

pub const PresentParams = struct {
    queue: *const core.Queue,
    cmd: *const core.CommandBuffer,
    in_flight_fence: vk.Fence,
};

pub const Error = error{
    NotImplemented,
    TargetNotReady,
    OutOfHostMemory,
    OutOfDeviceMemory,
    OutOfDateKHR,
    QueueCannotPresnt,
};

pub const VTable = struct {
    acquireFrame: *const fn (ptr: *anyopaque, in_flight_fence: vk.Fence) Error!FrameInfo = fallingAcquireFrame,
    presentFrame: *const fn (ptr: *anyopaque, params: PresentParams) Error!void = fallingPresentFrame,
    getExtent: *const fn (ptr: *anyopaque) vk.Extent2D = fallingGetExtent,
    getFinalLayout: *const fn (ptr: *anyopaque) vk.ImageLayout = fallingGetFinalLayout,
    deinit: *const fn (ptr: *anyopaque) void = fallingDeinit,
};

pub fn acquireFrame(self: *RenderTarget, in_flight_fence: vk.Fence) Error!FrameInfo {
    return self.vtable.acquireFrame(self.ptr, in_flight_fence);
}

pub fn presentFrame(self: *RenderTarget, params: PresentParams) Error!void {
    return self.vtable.presentFrame(self.ptr, params);
}

pub fn getExtent(self: *RenderTarget) vk.Extent2D {
    return self.vtable.getExtent(self.ptr);
}

pub fn getFinalLayout(self: *RenderTarget) vk.ImageLayout {
    return self.vtable.getFinalLayout(self.ptr);
}

pub fn deinit(self: *RenderTarget) void {
    self.vtable.deinit(self.ptr);
}

fn fallingAcquireFrame(_: *anyopaque, _: vk.Fence) Error!FrameInfo {
    return error.NotImplemented;
}

fn fallingPresentFrame(_: *anyopaque, _: PresentParams) Error!void {
    return error.NotImplemented;
}

fn fallingGetExtent(_: *anyopaque) vk.Extent2D {
    return .{ .width = 0, .height = 0 };
}

fn fallingGetFinalLayout(_: *anyopaque) vk.ImageLayout {
    return .undefined;
}

fn fallingDeinit(_: *anyopaque) void {}

const WsiInterface = @This();

const vk = @import("vulkan");

pub const VTable = struct {
    create: *const fn (*anyopaque) anyerror!void,
    destroy: *const fn (*anyopaque) void,

    acquire: *const fn (*anyopaque) anyerror!FrameImage,
    present: *const fn (*anyopaque, FrameImage) anyerror!void,

    resize: *const fn (*anyopaque, vk.Extent2D) anyerror!void,

    getExtent: *const fn (*anyopaque) vk.Extent2D,
    getFormat: *const fn (*anyopaque) vk.Format,
};

pub const Capabilities = struct {
    presentable: bool,
    resizable: bool,
    headless: bool,
};

pub const FrameImage = struct {
    image: vk.Image,
    view: vk.ImageView,
};

capabilities: Capabilities,

ptr: *anyopaque,
vtable: VTable,

pub fn initWindowed(_: anytype) WsiInterface {}

pub fn initHeadless() WsiInterface {}

pub fn acquire(self: *const WsiInterface) !FrameImage {
    return self.vtable.acquire(self.ptr);
}

pub fn present(self: *const WsiInterface, frame_image: FrameImage) !void {
    try self.vtable.present(self.ptr, frame_image);
}

pub fn resize(self: *const WsiInterface, extent: vk.Extent2D) !void {
    const old_extent = self.getExtent();

    if (old_extent.height != extent.height or
        old_extent.width != extent.width)
    {
        try self.vtable.resize(self.ptr, extent);
    }
}

pub fn getExtent(self: *const WsiInterface) vk.Extent2D {
    return self.vtable.getExtent(self.ptr);
}

const RenderTarget = @This();

image_views: []vk.ImageView,
images_format: vk.Format,

extent: vk.Extent2D,

pub const InitError = std.mem.Allocator.Error ||
    vk.DeviceWrapper.CreateImageViewError;

pub fn init(
    device: *const Device,
    allocator: std.mem.Allocator,
    images: []vk.Image,
    format: vk.Format,
    extent: vk.Extent2D,
) InitError!RenderTarget {
    const image_views = try allocator.alloc(vk.ImageView, images.len);
    errdefer allocator.free(image_views);

    var image_view_info: vk.ImageViewCreateInfo = .{
        .image = .null_handle,
        .view_type = .@"2d",
        .format = format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = .{
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
            .aspect_mask = .{ .color_bit = true },
        },
    };

    for (0..images.len) |i| {
        image_view_info.image = images[i];

        image_views[i] = try device.vkd.createImageView(
            device.handle,
            &image_view_info,
            device.vk_allocator,
        );
    }

    return .{
        .image_views = image_views,
        .images_format = format,
        .extent = extent,
    };
}

pub fn initFromSwapchain(
    swapchain: *const Swapchain,
    allocator: std.mem.Allocator,
) InitError!RenderTarget {
    return init(
        swapchain.device,
        allocator,
        swapchain.images,
        swapchain.surface_format.format,
        swapchain.extent,
    );
}

pub fn deinit(
    self: *const RenderTarget,
    device: *const Device,
    allocator: std.mem.Allocator,
) void {
    for (self.image_views) |image_view| {
        device.vkd.destroyImageView(
            device.handle,
            image_view,
            device.vk_allocator,
        );
    }

    allocator.free(self.image_views);
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const Swapchain = @import("Swapchain.zig");

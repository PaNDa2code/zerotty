const Target = @This();

context: *const Context,

images: []vk.Image,
image_views: []vk.ImageView,

image_format: vk.Format,
extent: vk.Extent2D,

const InitError = error{};

pub fn init(
    context: *const Context,
    images: []vk.Image,
) InitError!Target {}

const std = @import("std");
const vk = @import("vulkan");
const Context = @import("core/Context.zig");

const Image = @This();

handle: vk.Image,
views: []vk.ImageView = &.{},


const std = @import("std");
const vk = @import("vulkan");

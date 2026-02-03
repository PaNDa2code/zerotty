const Texture = @This();

image: *const core.Image,
sampler: vk.Sampler,

pub const InitError = error{};

pub fn init(device: *const core.Device, image: *const core.Image) InitError!Texture {}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");

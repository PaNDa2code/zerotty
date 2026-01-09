const Framebuffer = @This();

handle: vk.Framebuffer,

pub const InitError = vk.DeviceWrapper.CreateFramebufferError;

pub fn init() InitError!Framebuffer {}

const std = @import("std");
const vk = @import("vulkan");
const Context = @import("Context.zig");
const Target = @import("../Target.zig");

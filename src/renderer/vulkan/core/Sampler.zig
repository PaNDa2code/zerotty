const Sampler = @This();

handle: vk.Sampler,

pub fn init(device: *const Device) !Sampler {
    const sampler_info = vk.SamplerCreateInfo{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .max_lod = 0.0,
        .min_lod = 0.0,
        .mip_lod_bias = 0.0,
    };

    const handle = try device.vkd.createSampler(device.handle, &sampler_info, device.vk_allocator);

    return .{
        .handle = handle,
    };
}

pub fn deinit(self: *const Sampler, device: *const Device) void {
    device.vkd.destroySampler(device.handle, self.handle, device.vk_allocator);
}

const std = @import("std");
const vk = @import("vulkan");

const Device = @import("Device.zig");

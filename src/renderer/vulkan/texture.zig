const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn createAtlasTexture(self: *VulkanRenderer) !void {
    const vkd = self.device_wrapper;
    const vki = self.instance_wrapper;
    const mem_cb = self.vk_mem.vkAllocatorCallbacks();

    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(self.physical_device);

    const image_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .format = .r8_unorm,
        .extent = .{
            .width = @intCast(self.atlas.width),
            .height = @intCast(self.atlas.height),
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{
            .transfer_dst_bit = true,
            .sampled_bit = true,
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };

    const image = try vkd.createImage(self.device, &image_info, &mem_cb);

    const mem_requrements = vkd.getImageMemoryRequirements(self.device, image);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_requrements.size,
        .memory_type_index = findMemoryType(
            &mem_properties,
            mem_requrements.memory_type_bits,
            .{ .device_local_bit = true },
        ),
    };

    const image_memory = try vkd.allocateMemory(self.device, &alloc_info, &mem_cb);

    try vkd.bindImageMemory(self.device, image, image_memory, 0);

    const image_view_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = .r8_unorm,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{ .r = .one, .g = .one, .b = .one, .a = .r },
    };

    const image_view = try vkd.createImageView(self.device, &image_view_info, &mem_cb);

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

    const sampler = try vkd.createSampler(self.device, &sampler_info, &mem_cb);

    self.atlas_image = image;
    self.atlas_image_view = image_view;
    self.atlas_image_memory = image_memory;
    self.atlas_sampler = sampler;
}

pub fn uploadAtlas(self: *const VulkanRenderer) !void {
    const vkd = self.device_wrapper;

    const bytes = self.atlas.buffer.len;
    const statging_ptr: [*]u8 =
        @ptrCast(try vkd.mapMemory(self.device, self.staging_memory, 0, bytes, .{}));

    @memcpy(statging_ptr[0..bytes], self.atlas.buffer);

    vkd.unmapMemory(self.device, self.staging_memory);
}

const findMemoryType = @import("vertex_buffer.zig").findMemoryType;

const Image = @This();

handle: vk.Image,
view: vk.ImageView,

format: vk.Format,
extent: vk.Extent3D,

allocation: DeviceAllocation,

pub const Builder = struct {
    extent: vk.Extent3D = .{ .width = 1, .height = 1, .depth = 1 },
    format: vk.Format = .undefined,
    usage: vk.ImageUsageFlags = .{},

    image_type: vk.ImageType = .@"2d",
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    samples: vk.SampleCountFlags = .{ .@"1_bit" = true },
    tiling: vk.ImageTiling = .optimal,
    sharing_mode: vk.SharingMode = .exclusive,
    initial_layout: vk.ImageLayout = .undefined,
    flags: vk.ImageCreateFlags = .{},

    memory_flags: vk.MemoryPropertyFlags = .{
        .device_local_bit = true,
    },

    view_type: vk.ImageViewType = .@"2d",
    aspect_mask: vk.ImageAspectFlags = .{ .color_bit = true },
    component_mapping: vk.ComponentMapping = .{
        .r = .identity,
        .g = .identity,
        .b = .identity,
        .a = .identity,
    },

    pub fn new() Builder {
        return .{};
    }

    pub fn setSize(self: *Builder, width: u32, height: u32) *Builder {
        self.extent.width = width;
        self.extent.height = height;
        return self;
    }

    pub fn setFormat(self: *Builder, format: vk.Format) *Builder {
        self.format = format;
        return self;
    }

    pub fn setUsage(self: *Builder, usage: vk.ImageUsageFlags) *Builder {
        self.usage = usage;
        return self;
    }

    pub fn addUsage(self: *Builder, usage: vk.ImageUsageFlags) *Builder {
        self.usage = self.usage.merge(usage);
        return self;
    }

    pub fn setMipLevels(self: *Builder, levels: u32) *Builder {
        self.mip_levels = levels;
        return self;
    }

    pub fn setArrayLayers(self: *Builder, layers: u32) *Builder {
        self.array_layers = layers;
        return self;
    }

    pub fn setSamples(self: *Builder, samples: vk.SampleCountFlags) *Builder {
        self.samples = samples;
        return self;
    }

    pub fn setAspect(self: *Builder, aspect: vk.ImageAspectFlags) *Builder {
        self.aspect_mask = aspect;
        return self;
    }

    pub fn asColorAttachment(self: *Builder) *Builder {
        _ = self.addUsage(.{ .color_attachment_bit = true });
        _ = self.setFormat(.b8g8r8a8_srgb);
        return self;
    }

    pub fn asDepthAttachment(self: *Builder) *Builder {
        _ = self.addUsage(.{ .depth_stencil_attachment_bit = true });
        _ = self.setFormat(.d32_sfloat);
        _ = self.setAspect(.{ .depth_bit = true });
        self.memory_flags = .{ .device_local_bit = true };
        return self;
    }

    pub fn asTexture(self: *Builder) *Builder {
        _ = self.addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true });
        _ = self.setMipLevels(4);
        return self;
    }

    pub const BuildError = vk.DeviceWrapper.CreateImageError ||
        vk.DeviceWrapper.CreateImageViewError ||
        DeviceAllocator.AllocError ||
        vk.DeviceWrapper.BindImageMemoryError;

    pub fn build(self: *Builder, device_allocator: *DeviceAllocator) BuildError!Image {
        const device = device_allocator.device;

        const image_info = vk.ImageCreateInfo{
            .flags = self.flags,
            .image_type = self.image_type,
            .format = self.format,
            .extent = self.extent,
            .mip_levels = self.mip_levels,
            .array_layers = self.array_layers,
            .samples = self.samples,
            .tiling = self.tiling,
            .usage = self.usage,
            .sharing_mode = self.sharing_mode,
            .queue_family_index_count = 0,
            .p_queue_family_indices = null,
            .initial_layout = self.initial_layout,
        };

        const handle = try device.vkd.createImage(
            device.handle,
            &image_info,
            device.vk_allocator,
        );

        errdefer device.vkd.destroyImage(device.handle, handle, device.vk_allocator);

        const mem_requirements = device.vkd.getImageMemoryRequirements(
            device.handle,
            handle,
        );

        const allocation = try device_allocator.alloc(
            mem_requirements.size,
            mem_requirements.memory_type_bits,
            self.memory_flags,
        );

        try device.vkd.bindImageMemory(
            device.handle,
            handle,
            allocation.memory,
            allocation.offset,
        );

        errdefer device_allocator.free(allocation);

        const subresource_range = vk.ImageSubresourceRange{
            .aspect_mask = self.aspect_mask,
            .base_mip_level = 0,
            .level_count = self.mip_levels,
            .base_array_layer = 0,
            .layer_count = self.array_layers,
        };

        const view_info = vk.ImageViewCreateInfo{
            .image = handle,
            .view_type = self.view_type,
            .format = self.format,
            .components = self.component_mapping,
            .subresource_range = subresource_range,
        };

        const view = try device.vkd.createImageView(
            device.handle,
            &view_info,
            device.vk_allocator,
        );

        errdefer device.vkd.destroyImageView(self.device.handle, view, self.device.vk_allocator);

        return .{
            .handle = handle,
            .view = view,
            .allocation = allocation,
            .format = self.format,
            .extent = self.extent,
        };
    }
};

pub fn deinit(self: *const Image, device_allocator: *DeviceAllocator) void {
    const device = device_allocator.device;

    device.vkd.destroyImage(device.handle, self.handle, device.vk_allocator);
    device.vkd.destroyImageView(device.handle, self.view, device.vk_allocator);

    device_allocator.free(self.allocation);
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const DeviceAllocator = @import("../memory/DeviceAllocator.zig");
const DeviceAllocation = DeviceAllocator.DeviceAllocation;

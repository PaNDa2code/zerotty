const SwapChain = @This();

instance: *const Instance,
device: *const Device,

handle: vk.SwapchainKHR,
surface: vk.SurfaceKHR,

images: []vk.Image,
surface_format: vk.SurfaceFormatKHR,

extent: vk.Extent2D,
present_mode: vk.PresentModeKHR,

pub const SwapchainOptions = struct {
    extent: vk.Extent2D,
    presnt_mode: vk.PresentModeKHR = .fifo_khr,
    old_swapchain: vk.SwapchainKHR = .null_handle,

    image_count: u32 = 3,
    surface_format: vk.SurfaceFormatKHR = .{
        .format = .r8g8b8a8_uint,
        .color_space = .srgb_nonlinear_khr,
    },
};

pub const InitError = std.mem.Allocator.Error ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfacePresentModesKHRError ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfaceFormatsKHRError ||
    vk.InstanceWrapper.GetPhysicalDeviceSurfaceCapabilitiesKHRError ||
    vk.DeviceWrapper.CreateSwapchainKHRError;

pub fn init(
    instance: *const Instance,
    device: *const Device,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
    options: SwapchainOptions,
) InitError!SwapChain {
    const present_modes =
        try instance.vki.getPhysicalDeviceSurfacePresentModesAllocKHR(
            device.physical_device.handle,
            surface,
            allocator,
        );
    defer allocator.free(present_modes);

    const surface_formats =
        try instance.vki.getPhysicalDeviceSurfaceFormatsAllocKHR(
            device.physical_device.handle,
            surface,
            allocator,
        );
    defer allocator.free(surface_formats);

    const surface_format = chooseSurfaceFormat(options.surface_format, surface_formats);
    const present_mode = choosePresentMode(options.presnt_mode, present_modes);

    const surface_caps =
        try instance.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(
            device.physical_device.handle,
            surface,
        );

    const extent = chooseExtent(
        &options.extent,
        &surface_caps.min_image_extent,
        &surface_caps.max_image_extent,
        &surface_caps.current_extent,
    );

    const image_count = chooseImageCount(
        options.image_count,
        surface_caps.min_image_count,
        surface_caps.max_image_count,
    );

    const composite_alpha = chooseCompositeAlpha(surface_caps.supported_composite_alpha);

    const swapchain_info = vk.SwapchainCreateInfoKHR{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = null,
        .pre_transform = surface_caps.current_transform,
        .composite_alpha = composite_alpha,
        .present_mode = present_mode,
        .clipped = .true,

        .old_swapchain = options.old_swapchain,
    };

    const handle = try device.vkd.createSwapchainKHR(
        device.handle,
        &swapchain_info,
        instance.vk_allocator,
    );

    const images = try device.vkd.getSwapchainImagesAllocKHR(
        device.handle,
        handle,
        allocator,
    );

    return .{
        .instance = instance,
        .device = device,

        .handle = handle,
        .surface = surface,

        .images = images,
        .surface_format = surface_format,

        .extent = extent,
        .present_mode = present_mode,
    };
}

pub const RecreateError = InitError || error{};

pub fn recreate(
    self: *SwapChain,
    allocator: std.mem.Allocator,
    extent: vk.Extent2D,
) RecreateError!void {
    const new = try init(
        self.instance,
        self.device,
        allocator,
        self.surface,
        .{
            .extent = extent,
            .presnt_mode = self.present_mode,
            .old_swapchain = self.handle,

            .surface_format = self.surface_format,
        },
    );
    self.deinit(allocator);

    self.* = new;
}

pub fn deinit(self: *const SwapChain, allocator: std.mem.Allocator) void {
    self.device.vkd.destroySwapchainKHR(
        self.device.handle,
        self.handle,
        self.instance.vk_allocator,
    );

    allocator.free(self.images);
}

fn chooseExtent(
    requested: *const vk.Extent2D,
    min: *const vk.Extent2D,
    max: *const vk.Extent2D,
    current: *const vk.Extent2D,
) vk.Extent2D {
    if (current.width == std.math.maxInt(u32) or
        current.height == std.math.maxInt(u32))
        return requested.*;

    if (requested.width == 0 or requested.height == 0)
        return current.*;

    return .{
        .width = std.math.clamp(requested.width, min.width, max.width),
        .height = std.math.clamp(requested.height, min.height, max.height),
    };
}

fn chooseImageCount(requested: u32, min: u32, max: u32) u32 {
    const upper = if (max != 0) max else requested;
    return std.math.clamp(requested, min, upper);
}

fn chooseSurfaceFormat(
    requested: vk.SurfaceFormatKHR,
    available: []vk.SurfaceFormatKHR,
) vk.SurfaceFormatKHR {
    for (available) |format| {
        if (format.format == requested.format and
            format.color_space == requested.color_space)
        {
            return format;
        }
    }
    return available[0];
}

fn choosePresentMode(
    requested: vk.PresentModeKHR,
    available: []vk.PresentModeKHR,
) vk.PresentModeKHR {
    for (available) |mode| {
        if (mode == requested) {
            return mode;
        }
    }
    return .fifo_khr;
}

fn chooseCompositeAlpha(supported: vk.CompositeAlphaFlagsKHR) vk.CompositeAlphaFlagsKHR {
    const preferred = [_]vk.CompositeAlphaFlagsKHR{
        .{ .inherit_bit_khr = true },
        .{ .opaque_bit_khr = true },
        .{ .pre_multiplied_bit_khr = true },
        .{ .post_multiplied_bit_khr = true },
    };

    for (preferred) |flag| {
        if (supported.contains(flag)) {
            return flag;
        }
    }
    return .{};
}

const std = @import("std");
const vk = @import("vulkan");
const Instance = @import("Instance.zig");
const Device = @import("Device.zig");

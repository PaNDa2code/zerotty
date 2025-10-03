const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

const helpers = @import("helpers/root.zig");
const QueueFamilyIndices = helpers.physical_device.QueueFamilyIndices;

pub fn createSwapChain(self: *VulkanRenderer, allocator: Allocator) !void {
    const vk_mem_cb = &self.vk_mem.vkAllocatorCallbacks();

    self.swap_chain = try _createSwapChain(
        self.instance_wrapper,
        self.device_wrapper,
        self.physical_device,
        self.device,
        self.surface,
        self.queue_family_indcies,
        self.window_height,
        self.window_width,
        &self.swap_chain_extent,
        &self.swap_chain_format,
        allocator,
        vk_mem_cb,
    );

    self.swap_chain_images = try getSwapChainImages(self.device_wrapper, self.swap_chain, self.device, allocator);

    self.swap_chain_image_views = try createImageViews(
        self.device_wrapper,
        self.swap_chain_images,
        self.swap_chain_format,
        self.device,
        allocator,
        vk_mem_cb,
    );
}

fn _createSwapChain(
    vki: *const vk.InstanceWrapper,
    vkd: *const vk.DeviceWrapper,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    queue_family_indices: QueueFamilyIndices,
    height: u32,
    width: u32,
    swap_chain_extent: *vk.Extent2D,
    swap_chain_format: *vk.Format,
    allocator: Allocator,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.SwapchainKHR {
    const caps: vk.SurfaceCapabilitiesKHR =
        try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);

    const present_modes =
        try vki.getPhysicalDeviceSurfacePresentModesAllocKHR(
            physical_device,
            surface,
            allocator,
        );
    defer allocator.free(present_modes);

    const formats = try vki.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(formats);

    const format = chooseSwapSurfaceFormat(formats);
    const present_mode = chooseSwapPresentMode(present_modes);

    var image_count = caps.min_image_count + 1;

    if (caps.max_image_count != 0 and image_count > caps.max_image_count)
        image_count = caps.max_image_count;

    const extent: vk.Extent2D =
        if (caps.current_extent.width == std.math.maxInt(u32) or
        caps.current_extent.height == std.math.maxInt(u32))
            .{
                .height = height,
                .width = width,
            }
        else
            caps.current_extent;

    const same_queue =
        queue_family_indices.present_family == queue_family_indices.graphics_family;

    const p_queue_family_indices = &[_]u32{
        queue_family_indices.graphics_family,
        queue_family_indices.present_family,
    };

    const swap_chain_create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = format.format,
        .image_color_space = format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = if (same_queue) .exclusive else .concurrent,
        .queue_family_index_count = if (same_queue) 0 else 2,
        .p_queue_family_indices = if (same_queue) null else p_queue_family_indices,
        .pre_transform = caps.current_transform,
        .composite_alpha = pickCompositeAlpha(caps.supported_composite_alpha),
        .present_mode = present_mode,
        .clipped = .true,
    };

    const swap_chain = try vkd.createSwapchainKHR(device, &swap_chain_create_info, vk_mem_cb);

    swap_chain_extent.* = extent;
    swap_chain_format.* = format.format;

    return swap_chain;
}

fn createImageViews(
    vkd: *const vk.DeviceWrapper,
    images: []const vk.Image,
    swap_chain_format: vk.Format,
    device: vk.Device,
    allocator: Allocator,
    vk_mem_cb: *const vk.AllocationCallbacks,
) ![]vk.ImageView {
    const image_views = try allocator.alloc(vk.ImageView, images.len);
    errdefer allocator.free(image_views);

    for (images, 0..) |image, i| {
        const image_view_create_info: vk.ImageViewCreateInfo = .{
            .image = image,
            .view_type = .@"2d",
            .format = swap_chain_format,
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

        image_views[i] = try vkd.createImageView(device, &image_view_create_info, vk_mem_cb);
    }

    return image_views;
}

fn chooseSwapSurfaceFormat(formats: []const vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    for (formats) |*format| {
        if (format.format == .b8g8r8_srgb and format.color_space == .srgb_nonlinear_khr)
            return format.*;
    }
    return formats[0];
}

fn chooseSwapPresentMode(modes: []const vk.PresentModeKHR) vk.PresentModeKHR {
    var presend_mode = vk.PresentModeKHR.fifo_khr;

    for (modes) |mode| {
        if (mode == .mailbox_khr) {
            presend_mode = mode;
            break;
        } else if (mode == .immediate_khr) {
            presend_mode = mode;
        }
    }

    return presend_mode;
}

fn pickCompositeAlpha(supported: vk.CompositeAlphaFlagsKHR) vk.CompositeAlphaFlagsKHR {
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

fn getSwapChainImages(
    vkd: *const vk.DeviceWrapper,
    swap_chain: vk.SwapchainKHR,
    device: vk.Device,
    allocator: Allocator,
) ![]vk.Image {
    return try vkd.getSwapchainImagesAllocKHR(device, swap_chain, allocator);
}

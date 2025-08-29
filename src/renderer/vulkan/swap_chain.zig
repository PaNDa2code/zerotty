const std = @import("std");
const vk = @import("vulkan");

const Allocator = std.mem.Allocator;

const VulkanRenderer = @import("Vulkan.zig");

pub fn createSwapChain(self: *VulkanRenderer, allocator: Allocator) !void {
    self.swap_chain = try _createSwapChain(
        self.instance_wrapper,
        self.device_wrapper,
        self.physical_device,
        self.device,
        self.surface,
        self.window_height,
        self.window_width,
        allocator,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn _createSwapChain(
    vki: *const vk.InstanceWrapper,
    vkd: *const vk.DeviceWrapper,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    height: u32,
    width: u32,
    allocator: Allocator,
    vk_mem_cb: *const vk.AllocationCallbacks,
) !vk.SwapchainKHR {
    const caps: vk.SurfaceCapabilitiesKHR =
        try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);

    const swap_chain_extent: vk.Extent2D =
        if (caps.current_extent.width == -1 or caps.current_extent.height == -1)
            .{
                .highet = height,
                .width = width,
            }
        else
            caps.current_extent;

    var present_modes_count: u32 = 0;

    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &present_modes_count,
        null,
    );

    const present_modes = try vki.getPhysicalDeviceSurfacePresentModesAllocKHR(physical_device, surface, allocator);
    defer allocator.free(present_modes);

    var present_mode: vk.PresentModeKHR = .fifo_khr;

    for (present_modes) |mode| {
        if (mode == .mailbox_khr) {
            present_mode = .mailbox_khr;
            break;
        }
        if (mode == .immediate_khr)
            present_mode = .immediate_khr;
    }

    const formats = try vki.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(formats);
    std.log.debug("formats = {any}", .{formats});

    var image_count = caps.min_image_count + 1;

    if (caps.max_image_count != 0 and image_count > caps.max_image_count)
        image_count = caps.max_image_count;

    const swap_chain_create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = formats[0].format,
        .image_color_space = .srgb_nonlinear_khr,
        .image_extent = swap_chain_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = &.{0},
        .pre_transform = .{ .identity_bit_khr = true },
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = .false,
    };

    return try vkd.createSwapchainKHR(device, &swap_chain_create_info, vk_mem_cb);
}

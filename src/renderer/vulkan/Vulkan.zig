const VulkanRenderer = @This();

base_wrapper: *vk.BaseWrapper,
instance_wrapper: *vk.InstanceWrapper,
device_wrapper: *vk.DeviceWrapper,

instance: vk.Instance,
debug_messenger: vk.DebugUtilsMessengerEXT,
physical_device: vk.PhysicalDevice, // GPU
device: vk.Device, // GPU drivers
swap_chain: vk.SwapchainKHR,
surface: vk.SurfaceKHR, // Window surface
vk_mem: *VkAllocatorAdapter,
window_height: u32,
window_width: u32,
cmd_pool: vk.CommandPool,
cmd_buffers: []const vk.CommandBuffer,

pipe_line: PipeLine,

grid: Grid,

const log = std.log.scoped(.Renderer);

pub fn init(window: *Window, allocator: Allocator) !VulkanRenderer {
    var self: VulkanRenderer = undefined;

    self.vk_mem = try allocator.create(VkAllocatorAdapter);
    self.vk_mem.initInPlace(allocator);
    errdefer self.vk_mem.deinit();

    const vk_mem_cb = self.vk_mem.vkAllocatorCallbacks();

    self.base_wrapper = try allocAndLoad(vk.BaseWrapper, allocator, baseGetInstanceProcAddress, .{});

    try @import("instance.zig").createInstance(&self);

    const vki = try allocAndLoad(vk.InstanceWrapper, allocator, self.base_wrapper.dispatch.vkGetInstanceProcAddr.?, .{self.instance});
    errdefer vki.destroyInstance(self.instance, &vk_mem_cb);

    self.instance_wrapper = vki;
    try @import("debug.zig").setupDebugMessenger(&self);

    try @import("win_surface.zig").createWindowSurface(&self, window);
    errdefer vki.destroySurfaceKHR(self.instance, self.surface, &vk_mem_cb);

    var physical_devices: []vk.PhysicalDevice = &.{};
    var queue_family_indcies: []@import("physical_device.zig").QueueFamilyIndices = &.{};

    try @import("physical_device.zig").pickPhysicalDevicesAlloc(&self, allocator, &physical_devices, &queue_family_indcies);

    defer allocator.free(queue_family_indcies);
    defer allocator.free(physical_devices);

    try @import("device.zig").createDevice(&self, physical_devices[0], queue_family_indcies[0]);
    self.physical_device = physical_devices[0];

    const vkd = try allocAndLoad(vk.DeviceWrapper, allocator, vki.dispatch.vkGetDeviceProcAddr.?, .{self.device});
    errdefer vkd.destroyDevice(self.device, &vk_mem_cb);

    const caps: vk.SurfaceCapabilitiesKHR =
        try vki.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface);

    const swap_chain_extent: vk.Extent2D =
        if (caps.current_extent.width == -1 or caps.current_extent.height == -1)
            .{
                .highet = window.height,
                .width = window.width,
            }
        else
            caps.current_extent;

    var present_modes_count: u32 = 0;

    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(
        self.physical_device,
        self.surface,
        &present_modes_count,
        null,
    );

    const present_modes = try allocator.alloc(vk.PresentModeKHR, present_modes_count);
    defer allocator.free(present_modes);

    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(
        self.physical_device,
        self.surface,
        &present_modes_count,
        present_modes.ptr,
    );

    var present_mode: vk.PresentModeKHR = .fifo_khr;

    for (present_modes) |mode| {
        if (mode == .mailbox_khr) {
            present_mode = .mailbox_khr;
            break;
        }
        if (mode == .immediate_khr)
            present_mode = .immediate_khr;
    }

    const formats = try vki.getPhysicalDeviceSurfaceFormatsAllocKHR(self.physical_device, self.surface, allocator);
    defer allocator.free(formats);

    std.debug.assert(caps.max_image_count > 1);

    var image_count = caps.min_image_count + 1;

    if (caps.max_image_count < image_count)
        image_count = caps.max_image_count;

    const swap_chain_create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = self.surface,
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
        .clipped = 0,
    };

    const swap_chain = try vkd.createSwapchainKHR(self.device, &swap_chain_create_info, &vk_mem_cb);

    var cmd_pool: vk.CommandPool = .null_handle;
    const cmd_buffers = try allocCmdBuffers(allocator, vkd, self.device, image_count, &cmd_pool, &vk_mem_cb);

    return .{
        .swap_chain = swap_chain,
        .device = self.device,
        .instance = self.instance,
        .debug_messenger = self.debug_messenger,
        .physical_device = self.physical_device,
        .surface = self.surface,
        .base_wrapper = self.base_wrapper,
        .instance_wrapper = vki,
        .device_wrapper = vkd,
        .vk_mem = self.vk_mem,
        .window_height = window.height,
        .window_width = window.width,
        .cmd_pool = cmd_pool,
        .cmd_buffers = cmd_buffers,
        .pipe_line = undefined, //try .init(vkd, device, &vk_mem_cb, caps.current_extent),
        .grid = try Grid.create(allocator, .{}),
    };
}

fn allocAndLoad(T: type, allocator: Allocator, loader: anytype, loader_args: anytype) !*T {
    const ptr = try allocator.create(T);
    ptr.* = @call(.auto, T.load, loader_args ++ .{loader});
    return ptr;
}

fn allocCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    primary_count: usize,
    p_cmd_pool: *vk.CommandPool,
    vk_mem_cb: *const vk.AllocationCallbacks,
) ![]const vk.CommandBuffer {
    const cmd_pool_create_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = 0,
    };

    const cmd_pool = try vkd.createCommandPool(device, &cmd_pool_create_info, vk_mem_cb);
    errdefer vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);

    const cmd_buffer_alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = cmd_pool,
        .command_buffer_count = @intCast(primary_count),
        .level = .primary,
    };

    const cmd_buffers = try allocator.alloc(vk.CommandBuffer, primary_count);
    errdefer allocator.free(cmd_buffers);

    try vkd.allocateCommandBuffers(device, &cmd_buffer_alloc_info, cmd_buffers.ptr);

    p_cmd_pool.* = cmd_pool;

    return cmd_buffers;
}

fn freeCmdBuffers(
    allocator: Allocator,
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    cmd_pool: vk.CommandPool,
    buffers: []const vk.CommandBuffer,
    vk_mem_cb: *const vk.AllocationCallbacks,
) void {
    vkd.freeCommandBuffers(device, cmd_pool, @intCast(buffers.len), buffers.ptr);
    vkd.destroyCommandPool(device, cmd_pool, vk_mem_cb);
    allocator.free(buffers);
}

fn setImageLayout(
    cmd_buffer: vk.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) !void {
    _ = cmd_buffer;
    var src_access_mask: vk.AccessFlags = .{};
    var dst_access_mask: vk.AccessFlags = .{};

    switch (old_layout) {
        .preinitialized => {
            src_access_mask.host_write_bit = true;
            src_access_mask.host_read_bit = true;
        },
        .attachment_optimal => {
            src_access_mask.color_attachment_write_bit = true;
        },
        .depth_stentcil_attachment_optimal => {
            src_access_mask.depth_stencil_attachment_write_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.shader_read_bit = true;
        },
        else => {},
    }

    switch (new_layout) {
        .transfer_dst_optimal => {
            dst_access_mask.transfer_write_bit = true;
        },
        .transfer_src_optimal => {
            src_access_mask.transfer_read_bit = true;
            dst_access_mask.transfer_read_bit = true;
        },
        .attachment_optimal => {
            dst_access_mask.color_attachment_write_bit = true;
            src_access_mask.transfer_read_bit = true;
        },
        .depth_stencil_attachment_optimal => {
            dst_access_mask.depth_stencil_attachment_write_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.host_write_bit = true;
            src_access_mask.transfer_write_bit = true;
            dst_access_mask.shader_read_bit = true;
        },
        else => {},
    }
    const image_barriar: vk.ImageMemoryBarrier = .{
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .image = image,
        .subresource_range = .{
            .aspect_mask = aspects,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };

    _ = image_barriar;
}

fn baseGetInstanceProcAddress(_: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction {
    const vk_lib_name = if (os_tag == .windows) "vulkan-1" else "libvulkan.so.1";
    var vk_lib = std.DynLib.open(vk_lib_name) catch return null;

    return @ptrCast(vk_lib.lookup(*anyopaque, std.mem.span(procname)));
}

pub fn deinit(self: *VulkanRenderer) void {
    const allocator = self.vk_mem.allocator;
    const cb = self.vk_mem.vkAllocatorCallbacks();

    const vki = self.instance_wrapper;
    const vkd = self.device_wrapper;

    // self.pipe_line.deinit(vkd, self.device, &cb);

    freeCmdBuffers(self.vk_mem.allocator, vkd, self.device, self.cmd_pool, self.cmd_buffers, &cb);

    vkd.destroySwapchainKHR(self.device, self.swap_chain, &cb);
    vkd.destroyDevice(self.device, &cb);

    vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, &cb);
    vki.destroySurfaceKHR(self.instance, self.surface, &cb);
    vki.destroyInstance(self.instance, &cb);

    allocator.destroy(self.base_wrapper);
    allocator.destroy(self.instance_wrapper);
    allocator.destroy(self.device_wrapper);

    self.vk_mem.deinit();
    allocator.destroy(self.vk_mem);
}

pub fn clearBuffer(self: *VulkanRenderer, color: ColorRGBA) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *VulkanRenderer, width: u32, height: u32) !void {
    _ = self;
    _ = width;
    _ = height;
}

pub fn presentBuffer(self: *VulkanRenderer) void {
    _ = self;
}

pub fn renaderGrid(self: *VulkanRenderer) void {
    _ = self;
}

pub fn setCell(
    self: *VulkanRenderer,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBA,
    bg_color: ?ColorRGBA,
) !void {
    _ = self; // autofix
    _ = row; // autofix
    _ = col; // autofix
    _ = char_code; // autofix
    _ = fg_color; // autofix
    _ = bg_color; // autofix
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");
const common = @import("../common.zig");

const PipeLine = @import("PipeLine.zig");
const Window = @import("../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBA = common.ColorRGBA;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");
const Grid = @import("../Grid.zig");

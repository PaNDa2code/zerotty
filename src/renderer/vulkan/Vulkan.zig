const VulkanRenderer = @This();

base_wrapper: *vk.BaseWrapper,
instance_wrapper: *vk.InstanceWrapper,
device_wrapper: *vk.DeviceWrapper,

instance: vk.Instance,
debug_messenger: vk.DebugUtilsMessengerEXT,
physical_device: vk.PhysicalDevice, // GPU
device: vk.Device, // GPU drivers
graphics_queue: vk.Queue,
present_queue: vk.Queue,
swap_chain: vk.SwapchainKHR,
swap_chain_images: []vk.Image,
swap_chain_format: vk.Format,
swap_chain_extent: vk.Extent2D,
swap_chain_image_views: []vk.ImageView,

surface: vk.SurfaceKHR, // Window surface
vk_mem: *VkAllocatorAdapter,
window_height: u32,
window_width: u32,
cmd_pool: vk.CommandPool,
cmd_buffers: []const vk.CommandBuffer,

queue_family_indcies: QueueFamilyIndices,

pipe_line: PipeLine,
grid: Grid,

pub const log = std.log.scoped(.Renderer);

pub fn init(window: *Window, allocator: Allocator) !VulkanRenderer {
    var self: VulkanRenderer = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *VulkanRenderer, window: *Window, allocator: Allocator) !void {
    self.vk_mem = try allocator.create(VkAllocatorAdapter);
    errdefer allocator.destroy(self.vk_mem);

    self.vk_mem.initInPlace(allocator);
    errdefer self.vk_mem.deinit();

    const vk_mem_cb = self.vk_mem.vkAllocatorCallbacks();

    self.base_wrapper = try allocAndLoad(vk.BaseWrapper, allocator, baseGetInstanceProcAddress, .{});
    errdefer allocator.destroy(self.base_wrapper);

    try createInstance(self);

    const vki = try allocAndLoad(vk.InstanceWrapper, allocator, self.base_wrapper.dispatch.vkGetInstanceProcAddr.?, .{self.instance});
    errdefer vki.destroyInstance(self.instance, &vk_mem_cb);
    errdefer allocator.destroy(vki);

    self.instance_wrapper = vki;
    if (builtin.mode == .Debug) {
        try setupDebugMessenger(self);
        errdefer vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, &vk_mem_cb);
    }

    try createWindowSurface(self, window);
    errdefer vki.destroySurfaceKHR(self.instance, self.surface, &vk_mem_cb);

    var physical_devices: []vk.PhysicalDevice = &.{};
    var queue_family_indcies: []QueueFamilyIndices = &.{};

    try pickPhysicalDevicesAlloc(self, allocator, &physical_devices, &queue_family_indcies);

    defer allocator.free(queue_family_indcies);
    defer allocator.free(physical_devices);

    self.device = .null_handle;

    for (physical_devices, queue_family_indcies, 0..) |p_dev, queue_indces, i| {
        createLogicalDevice(self, p_dev, queue_indces) catch continue;
        self.physical_device = p_dev;
        log.info("using GPU{}", .{i});
        break;
    }

    if (self.device == .null_handle)
        return error.DeviceCreationFailed;

    const vkd = try allocAndLoad(vk.DeviceWrapper, allocator, vki.dispatch.vkGetDeviceProcAddr.?, .{self.device});
    errdefer vkd.destroyDevice(self.device, &vk_mem_cb);
    errdefer allocator.destroy(vkd);

    self.device_wrapper = vkd;

    getQueues(self);

    try createSwapChain(self, allocator);
    errdefer vkd.destroySwapchainKHR(self.device, self.swap_chain, &vk_mem_cb);

    try allocCmdBuffers(self, allocator);
    errdefer freeCmdBuffers(allocator, vkd, self.device, self.cmd_pool, self.cmd_buffers);

    self.grid = try Grid.create(allocator, .{});

    self.window_height = window.height;
    self.window_width = window.width;
}

fn allocAndLoad(T: type, allocator: Allocator, loader: anytype, loader_args: anytype) !*T {
    const ptr = try allocator.create(T);
    ptr.* = @call(.auto, T.load, loader_args ++ .{loader});
    return ptr;
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
    const vk_lib_name = if (os_tag == .windows) "vulkan-1.dll" else "libvulkan.so.1";
    // var vk_lib = std.DynLib.open(vk_lib_name) catch return null;
    // return @ptrCast(vk_lib.lookup(*anyopaque, std.mem.span(procname)));
    var vk_lib = DynamicLibrary.init(vk_lib_name) catch return null;
    return @ptrCast(vk_lib.getProcAddress(procname));
}

pub fn deinit(self: *VulkanRenderer) void {
    const allocator = self.vk_mem.allocator;
    const cb = self.vk_mem.vkAllocatorCallbacks();

    const vki = self.instance_wrapper;
    const vkd = self.device_wrapper;

    // self.pipe_line.deinit(vkd, self.device, &cb);

    freeCmdBuffers(self.vk_mem.allocator, vkd, self.device, self.cmd_pool, self.cmd_buffers, &cb);

    for (self.swap_chain_image_views) |view| {
        vkd.destroyImageView(self.device, view, &cb);
    }

    vkd.destroySwapchainKHR(self.device, self.swap_chain, &cb);
    vkd.destroyDevice(self.device, &cb);

    if (builtin.mode == .Debug)
        vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, &cb);

    vki.destroySurfaceKHR(self.instance, self.surface, &cb);
    vki.destroyInstance(self.instance, &cb);

    allocator.free(self.swap_chain_images);
    allocator.free(self.swap_chain_image_views);

    allocator.destroy(self.base_wrapper);
    allocator.destroy(self.instance_wrapper);
    allocator.destroy(self.device_wrapper);

    self.vk_mem.deinit();
    allocator.destroy(self.vk_mem);
}

pub fn clearBuffer(self: *VulkanRenderer, color: ColorRGBAf32) void {
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
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
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
const ColorRGBAu8 = common.ColorRGBAu8;
const ColorRGBAf32 = common.ColorRGBAf32;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");
const Grid = @import("../Grid.zig");

const QueueFamilyIndices = @import("physical_device.zig").QueueFamilyIndices;

const createInstance = @import("instance.zig").createInstance;
const setupDebugMessenger = @import("debug.zig").setupDebugMessenger;
const createWindowSurface = @import("win_surface.zig").createWindowSurface;
const pickPhysicalDevicesAlloc = @import("physical_device.zig").pickPhysicalDevicesAlloc;
const createLogicalDevice = @import("device.zig").createDevice;
const getQueues = @import("queues.zig").getQueues;
const createSwapChain = @import("swap_chain.zig").createSwapChain;
const allocCmdBuffers = @import("cmd_buffers.zig").allocCmdBuffers;
const freeCmdBuffers = @import("cmd_buffers.zig").freeCmdBuffers;

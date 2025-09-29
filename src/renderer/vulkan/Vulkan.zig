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

descriptor_set: vk.DescriptorSet,
descriptor_set_layout: vk.DescriptorSetLayout,
descriptor_pool: vk.DescriptorPool,

frame_buffers: []vk.Framebuffer,

vertex_buffer_size: usize,

vertex_buffer: vk.Buffer,
staging_buffer: vk.Buffer,
uniform_buffer: vk.Buffer,

vertex_memory: vk.DeviceMemory,
staging_memory: vk.DeviceMemory,
uniform_memory: vk.DeviceMemory,

image_available_semaphore: vk.Semaphore,
render_finished_semaphore: vk.Semaphore,
in_flight_fence: vk.Fence,

atlas_dirty: bool,
atlas_image: vk.Image,
atlas_image_view: vk.ImageView,
atlas_image_memory: vk.DeviceMemory,
atlas_sampler: vk.Sampler,

surface: vk.SurfaceKHR, // Window surface
vk_mem: *VkAllocatorAdapter,
window_height: u32,
window_width: u32,
cmd_pool: vk.CommandPool,
cmd_buffers: []const vk.CommandBuffer,
render_pass: vk.RenderPass,
pipe_line: vk.Pipeline,
pipe_line_layout: vk.PipelineLayout,

queue_family_indcies: QueueFamilyIndices,

atlas: Atlas,
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
    if (build_options.@"renderer-debug") {
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
        log.debug("using GPU{}", .{i});
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

    try createRenderPass(self);
    errdefer vkd.destroyRenderPass(self.device, self.render_pass, &vk_mem_cb);

    try createDescriptorSet(self);
    errdefer {
        // vkd.freeDescriptorSets(self.device, self.descriptor_pool, 1, &.{self.descriptor_set}) catch {};
        vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, &vk_mem_cb);
        vkd.destroyDescriptorPool(self.device, self.descriptor_pool, &vk_mem_cb);
    }

    try createPipeLine(self);
    errdefer vkd.destroyPipeline(self.device, self.pipe_line, &vk_mem_cb);

    try createFrameBuffers(self, allocator);

    try allocCmdBuffers(self, allocator);
    errdefer freeCmdBuffers(allocator, vkd, self.device, self.cmd_pool, self.cmd_buffers, &vk_mem_cb);

    self.atlas_dirty = true;

    self.atlas = try Atlas.create(allocator, 30, 20, 0, 128);

    const grid_rows = window.height / self.atlas.cell_height;
    const grid_cols = window.width / self.atlas.cell_width;

    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    const vertex_memory_size = grid_rows * grid_cols * @sizeOf(Grid.Cell);
    const altas_size = self.atlas.buffer.len;

    const staging_memory_size = @max(altas_size, vertex_memory_size);

    try createBuffers(self, vertex_memory_size, staging_memory_size);

    try createAtlasTexture(self);

    try createSyncObjects(self);

    try uploadVertexData(self);

    try updateUniformData(self);

    try uploadAtlas(self);

    try updateDescriptorSets(self);

    self.window_height = window.height;
    self.window_width = window.width;
}

fn allocAndLoad(T: type, allocator: Allocator, loader: anytype, loader_args: anytype) !*T {
    const ptr = try allocator.create(T);
    ptr.* = @call(.auto, T.load, loader_args ++ .{loader});
    return ptr;
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

    vkd.deviceWaitIdle(self.device) catch {};

    freeCmdBuffers(self.vk_mem.allocator, vkd, self.device, self.cmd_pool, self.cmd_buffers, &cb);

    for (self.swap_chain_image_views) |view| {
        vkd.destroyImageView(self.device, view, &cb);
    }

    for (self.frame_buffers) |buffer| {
        vkd.destroyFramebuffer(self.device, buffer, &cb);
    }
    allocator.free(self.frame_buffers);

    vkd.destroyBuffer(self.device, self.vertex_buffer, &cb);
    vkd.destroyBuffer(self.device, self.staging_buffer, &cb);
    vkd.destroyBuffer(self.device, self.uniform_buffer, &cb);

    vkd.freeMemory(self.device, self.vertex_memory, &cb);
    vkd.freeMemory(self.device, self.staging_memory, &cb);
    vkd.freeMemory(self.device, self.uniform_memory, &cb);

    vkd.destroyImageView(self.device, self.atlas_image_view, &cb);
    vkd.destroyImage(self.device, self.atlas_image, &cb);
    vkd.freeMemory(self.device, self.atlas_image_memory, &cb);
    vkd.destroySampler(self.device, self.atlas_sampler, &cb);

    vkd.destroySemaphore(self.device, self.image_available_semaphore, &cb);
    vkd.destroySemaphore(self.device, self.render_finished_semaphore, &cb);
    vkd.destroyFence(self.device, self.in_flight_fence, &cb);

    vkd.destroyPipeline(self.device, self.pipe_line, &cb);
    vkd.destroyRenderPass(self.device, self.render_pass, &cb);

    // vkd.freeDescriptorSets(self.device, self.descriptor_pool, 1, &.{self.descriptor_set}) catch {};
    vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, &cb);
    vkd.destroyDescriptorPool(self.device, self.descriptor_pool, &cb);

    vkd.destroyPipelineLayout(self.device, self.pipe_line_layout, &cb);

    vkd.destroySwapchainKHR(self.device, self.swap_chain, &cb);
    vkd.destroyDevice(self.device, &cb);

    if (build_options.@"renderer-debug")
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

    self.grid.free();
    self.atlas.deinit(allocator);
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
    drawFrame(self) catch @panic("drawFrame failed");
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
    try self.grid.set(.{
        .row = row,
        .col = col,
        .char = char_code,
        .fg_color = fg_color orelse .White,
        .bg_color = bg_color orelse .Black,
        .glyph_info = self.atlas.glyph_lookup_map.get(char_code) orelse self.atlas.glyph_lookup_map.get(' ').?,
    });
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");
const common = @import("../common.zig");

const Window = @import("../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = common.ColorRGBAu8;
const ColorRGBAf32 = common.ColorRGBAf32;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const VkAllocatorAdapter = @import("VkAllocatorAdapter.zig");
const Grid = @import("../Grid.zig");
const Atlas = @import("../../font/Atlas.zig");

const QueueFamilyIndices = @import("physical_device.zig").QueueFamilyIndices;

const createInstance = @import("instance.zig").createInstance;
const setupDebugMessenger = @import("debug.zig").setupDebugMessenger;
const createWindowSurface = @import("win_surface.zig").createWindowSurface;
const pickPhysicalDevicesAlloc = @import("physical_device.zig").pickPhysicalDevicesAlloc;
const createLogicalDevice = @import("device.zig").createDevice;
const getQueues = @import("queues.zig").getQueues;
const createSwapChain = @import("swap_chain.zig").createSwapChain;
const createRenderPass = @import("render_pass.zig").createRenderPass;
const createPipeLine = @import("pipe_line.zig").createPipeLine;
const createFrameBuffers = @import("frame_buffers.zig").createFrameBuffers;
const allocCmdBuffers = @import("cmd_buffers.zig").allocCmdBuffers;
const freeCmdBuffers = @import("cmd_buffers.zig").freeCmdBuffers;
const recordCommandBuffer = @import("cmd_buffers.zig").recordCommandBuffer;
const submitCmdBuffer = @import("cmd_buffers.zig").supmitCmdBuffer;
const createBuffers = @import("vertex_buffer.zig").createBuffers;
const uploadVertexData = @import("vertex_buffer.zig").uploadVertexData;
const createAtlasTexture = @import("texture.zig").createAtlasTexture;
const uploadAtlas = @import("texture.zig").uploadAtlas;
const updateDescriptorSets = @import("uniform_data.zig").updateDescriptorSets;
const updateUniformData = @import("uniform_data.zig").updateUniformData;
const createSyncObjects = @import("sync.zig").createSyncObjects;
const drawFrame = @import("frames.zig").drawFrame;
const createDescriptorSet = @import("descriptor.zig").createDescriptorSet;

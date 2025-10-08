const VulkanRenderer = @This();

_core: Core,
_swap_chain: SwapChain,
_pipe_line: Pipeline,
_buffers: Buffers,
_sync: Sync,
_cmd: Command,

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
render_finished_semaphores: []vk.Semaphore,
in_flight_fence: vk.Fence,

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

const Core = @import("Core.zig");
const SwapChain = @import("SwapChain.zig");
const Descriptor = @import("Descriptor.zig");
const Pipeline = @import("Pipeline.zig");
const Buffers = @import("Buffers.zig");
const Sync = @import("Sync.zig");
const Command = @import("Command.zig");

pub fn setup(self: *VulkanRenderer, window: *Window, allocator: Allocator) !void {
    const core = try Core.init(allocator, window);
    self._core = core;

    const _swap_chain = try SwapChain.init(&core, window.height, window.width);
    const descriptor = try Descriptor.init(&core);
    const _pipe_line = try Pipeline.init(&core, &_swap_chain, &descriptor);
    const _cmd = try Command.init(&core, 2);

    self.atlas = try Atlas.create(allocator, 30, 20, 0, 128);

    const grid_rows = window.height / self.atlas.cell_height;
    const grid_cols = window.width / self.atlas.cell_width;

    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    const vertex_memory_size = 1024 * 16;
    const altas_size = self.atlas.buffer.len;

    const staging_memory_size = @max(altas_size, vertex_memory_size);

    const _buffers = try Buffers.init(&core, .{
        .staging_size = staging_memory_size,
        .vertex_size = staging_memory_size,
        .uniform_size = 16 * 1024,
    });

    const _sync = try Sync.init(&core, &_swap_chain);

    self.vk_mem = self._core.vk_mem;
    errdefer allocator.destroy(self.vk_mem);

    const vk_mem_cb = self.vk_mem.vkAllocatorCallbacks();

    self.base_wrapper = @constCast(&core.dispatch.vkb);

    self.instance = core.instance;

    const vki = @constCast(&core.dispatch.vki);

    self.instance_wrapper = vki;

    if (build_options.@"renderer-debug") {
        try setupDebugMessenger(self);
    }

    errdefer if (build_options.@"renderer-debug")
        vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, &vk_mem_cb);

    self.surface = core.surface;

    self.physical_device = core.physical_device;

    self.device = core.device;

    const vkd = @constCast(&core.dispatch.vkd);

    self.device_wrapper = vkd;

    self.graphics_queue = core.graphics_queue;
    self.present_queue = core.present_queue;

    self.queue_family_indcies = .{
        .present_family = core.present_family_index,
        .graphics_family = core.graphics_family_index,
    };

    {
        self.swap_chain = _swap_chain.handle;
        self.swap_chain_images = _swap_chain.images;
        self.swap_chain_image_views = _swap_chain.image_views;
        self.swap_chain_format = _swap_chain.format;
        self.swap_chain_extent = _swap_chain.extent;
    }

    errdefer {
        for (self.swap_chain_image_views) |view| {
            vkd.destroyImageView(self.device, view, &vk_mem_cb);
        }
        vkd.destroySwapchainKHR(self.device, self.swap_chain, &vk_mem_cb);
    }

    {
        self.render_pass = _pipe_line.render_pass;
    }
    errdefer vkd.destroyRenderPass(self.device, self.render_pass, &vk_mem_cb);

    {
        self.descriptor_set = descriptor.set;
        self.descriptor_pool = descriptor.pool;
        self.descriptor_set_layout = descriptor.layout;
    }
    errdefer {
        vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, &vk_mem_cb);
        vkd.destroyDescriptorPool(self.device, self.descriptor_pool, &vk_mem_cb);
    }

    {
        self.pipe_line = _pipe_line.handle;
        self.pipe_line_layout = _pipe_line.layout;
    }
    errdefer {
        vkd.destroyPipeline(self.device, self.pipe_line, &vk_mem_cb);
        vkd.destroyPipelineLayout(self.device, self.pipe_line_layout, &vk_mem_cb);
    }

    {
        self.frame_buffers = _pipe_line.frame_buffers;
    }
    errdefer {
        for (self.frame_buffers) |buffer| {
            vkd.destroyFramebuffer(self.device, buffer, &vk_mem_cb);
        }
        allocator.free(self.frame_buffers);
    }

    {
        self.cmd_pool = _cmd.pool;
        self.cmd_buffers = _cmd.buffers;
    }
    errdefer {
        vkd.freeCommandBuffers(self.device, self.cmd_pool, @intCast(self.cmd_buffers.len), self.cmd_buffers.ptr);
        vkd.destroyCommandPool(self.device, self.cmd_pool, &vk_mem_cb);
        allocator.free(self.cmd_buffers);
    }

    {
        self.vertex_buffer = _buffers.vertex_buffer.handle;
        self.vertex_memory = _buffers.vertex_buffer.memory;
        self.vertex_buffer_size = _buffers.vertex_buffer.size;

        self.uniform_buffer = _buffers.uniform_buffer.handle;
        self.uniform_memory = _buffers.uniform_buffer.memory;

        self.staging_buffer = _buffers.staging_buffer.handle;
        self.staging_memory = _buffers.staging_buffer.memory;
    }
    errdefer {
        vkd.destroyBuffer(self.device, self.vertex_buffer, &vk_mem_cb);
        vkd.destroyBuffer(self.device, self.staging_buffer, &vk_mem_cb);
        vkd.destroyBuffer(self.device, self.uniform_buffer, &vk_mem_cb);
        vkd.freeMemory(self.device, self.vertex_memory, &vk_mem_cb);
        vkd.freeMemory(self.device, self.staging_memory, &vk_mem_cb);
        vkd.freeMemory(self.device, self.uniform_memory, &vk_mem_cb);
    }

    try createAtlasTexture(self);
    errdefer {
        vkd.destroyImageView(self.device, self.atlas_image_view, &vk_mem_cb);
        vkd.destroyImage(self.device, self.atlas_image, &vk_mem_cb);
        vkd.freeMemory(self.device, self.atlas_image_memory, &vk_mem_cb);
        vkd.destroySampler(self.device, self.atlas_sampler, &vk_mem_cb);
    }

    // try createSyncObjects(self, allocator);
    {
        self.render_finished_semaphores = _sync.render_finished_semaphores;
        self.image_available_semaphore = _sync.image_available_semaphores[0];
        self.in_flight_fence = _sync.in_flight_fences[0];
    }
    errdefer {
        for (self.render_finished_semaphores) |semaphore| {
            vkd.destroySemaphore(self.device, semaphore, &vk_mem_cb);
        }
        vkd.destroySemaphore(self.device, self.image_available_semaphore, &vk_mem_cb);
        vkd.destroyFence(self.device, self.in_flight_fence, &vk_mem_cb);
    }

    self.window_height = window.height;
    self.window_width = window.width;

    try updateUniformData(self);

    try uploadAtlas(self);

    try _buffers.stageVertexData(
        &core,
        &self.grid,
        &self.atlas,
    );

    try updateDescriptorSets(self);
}

pub fn deinit(self: *VulkanRenderer) void {
    const allocator = self.vk_mem.allocator;
    const cb = self.vk_mem.vkAllocatorCallbacks();

    const vki = self.instance_wrapper;
    const vkd = self.device_wrapper;

    vkd.deviceWaitIdle(self.device) catch {};

    vkd.freeCommandBuffers(self.device, self.cmd_pool, @intCast(self.cmd_buffers.len), self.cmd_buffers.ptr);
    vkd.destroyCommandPool(self.device, self.cmd_pool, &cb);
    allocator.free(self.cmd_buffers);

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

    for (self.render_finished_semaphores) |semaphore| {
        vkd.destroySemaphore(self.device, semaphore, &cb);
    }
    vkd.destroySemaphore(self.device, self.image_available_semaphore, &cb);
    vkd.destroyFence(self.device, self.in_flight_fence, &cb);
    allocator.free(self.render_finished_semaphores);

    vkd.destroyPipeline(self.device, self.pipe_line, &cb);
    vkd.destroyRenderPass(self.device, self.render_pass, &cb);
    vkd.destroyPipelineLayout(self.device, self.pipe_line_layout, &cb);

    vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, &cb);
    vkd.destroyDescriptorPool(self.device, self.descriptor_pool, &cb);

    vkd.destroySwapchainKHR(self.device, self.swap_chain, &cb);
    vkd.destroyDevice(self.device, &cb);

    if (build_options.@"renderer-debug")
        vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, &cb);

    vki.destroySurfaceKHR(self.instance, self.surface, &cb);
    vki.destroyInstance(self.instance, &cb);

    allocator.free(self.swap_chain_images);
    allocator.free(self.swap_chain_image_views);

    allocator.destroy(self._core.dispatch);

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
    const glyph_info = self.atlas.glyph_lookup_map.get(char_code) orelse self.atlas.glyph_lookup_map.get(' ').?;

    try self.grid.set(.{
        .row = row,
        .col = col,
        .char = char_code,
        .fg_color = fg_color orelse .White,
        .bg_color = bg_color orelse .Black,
        .glyph_info = glyph_info,
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

const helpers = @import("helpers/root.zig");
const QueueFamilyIndices = helpers.physical_device.QueueFamilyIndices;

const setupDebugMessenger = helpers.debug.setupDebugMessenger;
const allocCmdBuffers = @import("cmd_buffers.zig").allocCmdBuffers;
const recordCommandBuffer = @import("cmd_buffers.zig").recordCommandBuffer;
const createAtlasTexture = @import("texture.zig").createAtlasTexture;
const uploadAtlas = @import("texture.zig").uploadAtlas;
const updateDescriptorSets = @import("uniform_data.zig").updateDescriptorSets;
const updateUniformData = @import("uniform_data.zig").updateUniformData;
const drawFrame = @import("frames.zig").drawFrame;

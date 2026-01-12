const Backend = @This();

instance: *const Instance,
device: *const Device,

swapchain: Swapchain,
render_pass: RenderPass,
render_targets: []RenderTarget,

window_height: u32,
window_width: u32,

allocator_adapter: *AllocatorAdapter,

pub const log = std.log.scoped(.renderer);

pub fn init(window: *Window, allocator: Allocator) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator) !void {
    self.allocator_adapter = try AllocatorAdapter.init(allocator);

    const surface_creation_info = SurfaceCreationInfo.fromWindow(window);

    const instance = try allocator.create(Instance);

    instance.* = try Instance.init(
        allocator,
        &self.allocator_adapter.alloc_callbacks,
        surface_creation_info.instanceExtensions(),
    );
    errdefer instance.deinit();

    const surface = try createWindowSurface(instance, surface_creation_info);

    const device = try allocator.create(Device);
    device.* = try Device.init(
        allocator,
        instance,
        surface,
        SurfaceCreationInfo.deviceExtensions(),
    );
    errdefer device.deinit();

    self.instance = instance;
    self.device = device;

    self.swapchain =
        try Swapchain.init(self.instance, self.device, allocator, surface, .{
            .extent = .{
                .height = window.height,
                .width = window.width,
            },
        });

    self.render_targets = try RenderTarget.initFromSwapchain(&self.swapchain, allocator);

    var render_pass_builder = RenderPass.Builder.init(allocator);
    errdefer render_pass_builder.deinit();

    try render_pass_builder.addAttachment(.{
        .format = self.swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    });

    try render_pass_builder.addSubpass(.{
        .pipeline_bind_point = .graphics,
        .color_attachments = &.{
            .{ .attachment = 0, .layout = .color_attachment_optimal },
        },
    });

    try render_pass_builder.addDependency(.{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
    });

    self.render_pass = try render_pass_builder.build(self.device);

    const framebuffers = try allocator.alloc(Framebuffer, self.render_targets.len);

    for (0..framebuffers.len) |i| {
        framebuffers[i] = try Framebuffer.init(self.device, &self.render_pass, &self.render_targets[i]);
    }

    const descriptor_pool = try DescriptorPool.Builder
        .addPoolSize(.storage_buffer, 2)
        .addPoolSize(.combined_image_sampler, 1)
        .addPoolSize(.uniform_buffer, 1)
        .build(self.device);

    defer descriptor_pool.deinit();

    const descriptor_set_layout = try DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .addBinding(2, .storage_buffer, 1, .{ .vertex_bit = true })
        .addBinding(3, .storage_buffer, 1, .{ .vertex_bit = true })
        .build(self.device);

    defer descriptor_set_layout.deinit(self.device);

    _ = try DescriptorSet.init(&descriptor_pool, &descriptor_set_layout, allocator, &.{}, &.{});

    const pipeline_layout = try PipelineLayout.init(device, &.{descriptor_set_layout}, allocator);

    var vertex_shader = ShaderModule.init(
        &assets.shaders.cell_vert,
        "main",
        .vertex,
    );

    var fragment_shader = ShaderModule.init(
        &assets.shaders.cell_frag,
        "main",
        .fragment,
    );

    var pipeline_builder = Pipeline.Builder.init(device, allocator);
    defer pipeline_builder.deinit();

    pipeline_builder.setLayout(&pipeline_layout);
    pipeline_builder.setRenderPass(&self.render_pass);

    try pipeline_builder.setVertexInput(vertex_input.bindings, vertex_input.attributes);

    try pipeline_builder.addShader(&vertex_shader);
    try pipeline_builder.addShader(&fragment_shader);

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(framebuffers[0].extent.width),
        .height = @floatFromInt(framebuffers[0].extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = framebuffers[0].extent,
    };

    pipeline_builder.setViewport(viewport);
    pipeline_builder.setScissor(scissor);

    try pipeline_builder.addDynamicState(.viewport);
    try pipeline_builder.addDynamicState(.scissor);

    try pipeline_builder.addColorBlendAttachment(.{
        .blend_enable = .false,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{
            .r_bit = true,
            .g_bit = true,
            .b_bit = true,
            .a_bit = true,
        },
    });

    const pipeline = try pipeline_builder.build();

    _ = pipeline;

    const cmd_pool = try CommandPool.init(
        device,
        device.physical_device.graphic_family_index,
    );
    defer cmd_pool.deinit();

    var sec_cmd_buffer = try cmd_pool.allocBuffer(.secondary);
    try sec_cmd_buffer.reset(false);
    try sec_cmd_buffer.beginSecondary(null, null, 0, .{});
    try sec_cmd_buffer.end();
    var cmd_buffer = try cmd_pool.allocBuffer(.primary);
    try cmd_buffer.begin(.{});
    try cmd_buffer.executeCommand(sec_cmd_buffer.handle);
    try cmd_buffer.beginRenderPass(&self.render_pass, framebuffers[0], null, .secondary_command_buffers);
    try cmd_buffer.endRenderPass();
    try cmd_buffer.end();

    var vram_allocator = DeviceAllocator.init(device, allocator);

    var vertex_buffer = try Buffer.init(
        device,
        1024,
        .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
        .exclusive,
    );

    const vertex_alloc = try vram_allocator.alloc(
        vertex_buffer.mem_requirements.size,
        vertex_buffer.mem_requirements.memory_type_bits,
        .{ .device_local_bit = true, .host_visible_bit = true },
    );

    try vertex_buffer.bindMemory(vertex_alloc);

    const vertex_buffer_descriptor_info = vertex_buffer.getDescriptorBufferInfo();

    var descriptor_set = try DescriptorSet.init(
        &descriptor_pool,
        &descriptor_set_layout,
        allocator,
        &.{},
        &.{},
    );

    const buffer_infos = try allocator.alloc([]vk.DescriptorBufferInfo, 1);
    buffer_infos[0] = try allocator.alloc(vk.DescriptorBufferInfo, 1);

    buffer_infos[0][0] = vertex_buffer_descriptor_info;

    try descriptor_set.reset(buffer_infos, &.{});

    descriptor_set.update();
}

pub fn deinit(self: *Backend) void {
    const allocator = self.allocator_adapter.allocator;

    self.swapchain.deinit(allocator);

    self.instance.vki.destroySurfaceKHR(
        self.instance.handle,
        self.swapchain.surface,
        self.instance.vk_allocator,
    );

    self.render_pass.deinit();

    for (self.render_targets) |target| {
        target.deinit(self.device, self.allocator_adapter.allocator);
    }

    self.device.deinit();
    self.instance.deinit();

    self.allocator_adapter.deinit();

    allocator.destroy(self.instance);
    allocator.destroy(self.device);
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    try self.swapchain.recreate(
        self.allocator_adapter.allocator,
        .{ .width = width, .height = height },
    );

    for (self.render_targets) |target| {
        target.deinit(self.device, self.allocator_adapter.allocator);
    }

    self.render_targets = try RenderTarget.initFromSwapchain(
        &self.swapchain,
        self.allocator_adapter.allocator,
    );
}

pub fn presentBuffer(self: *Backend) void {
    _ = self;
}

pub fn renaderGrid(self: *Backend) void {
    _ = self;
}

pub fn setCell(
    self: *Backend,
    row: u32,
    col: u32,
    char_code: u32,
    fg_color: ?ColorRGBAu8,
    bg_color: ?ColorRGBAu8,
) !void {
    _ = bg_color; // autofix
    _ = fg_color; // autofix
    _ = char_code; // autofix
    _ = col; // autofix
    _ = row; // autofix
    _ = self; // autofix

}

const std = @import("std");
const builtin = @import("builtin");
const assets = @import("assets");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");

const Instance = @import("core/Instance.zig");
const Device = @import("core/Device.zig");
const Swapchain = @import("core/Swapchain.zig");
const RenderPass = @import("core/RenderPass.zig");
const DescriptorPool = @import("core/DescriptorPool.zig");
const DescriptorSetLayout = @import("core/DescriptorSetLayout.zig");
const DescriptorSet = @import("core/DescriptorSet.zig");
const RenderTarget = @import("core/RenderTarget.zig");
const Framebuffer = @import("core/Framebuffer.zig");
const CommandPool = @import("core/CommandPool.zig");
const CommandBuffer = @import("core/CommandBuffer.zig");
const Pipeline = @import("core/Pipeline.zig");
const PipelineLayout = @import("core/PipelineLayout.zig");
const ShaderModule = @import("core/ShaderModule.zig");
const Buffer = @import("core/Buffer.zig");
const DeviceAllocator = @import("memory/DeviceAllocator.zig");
const window_surface = @import("window_surface.zig");
const SurfaceCreationInfo = window_surface.SurfaceCreationInfo;
const createWindowSurface = window_surface.createWindowSurface;

const Window = @import("../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("../common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("../common/color.zig").ColorRGBAf32;
const DynamicLibrary = @import("../../DynamicLibrary.zig");
const AllocatorAdapter = @import("memory/AllocatorAdapter.zig");
const Grid = @import("../../Grid.zig");
const Atlas = @import("../../font/Atlas.zig");

const vertex_input = Pipeline.VertexInputDescriptionBuilder
    .addBinding(.{ .binding = 0, .stride = 0, .input_rate = .instance })
    .addAttribute(.{ .location = 1, .binding = 0, .format = .r32_uint, .offset = 0 })
    .addAttribute(.{ .location = 2, .binding = 0, .format = .r32_uint, .offset = 0 })
    .addAttribute(.{ .location = 3, .binding = 0, .format = .r32_uint, .offset = 0 })
    .collect();

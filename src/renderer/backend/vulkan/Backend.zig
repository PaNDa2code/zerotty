const Backend = @This();

context: *const Context,

swapchain: Swapchain,
render_pass: RenderPass,
target: Target,

window_height: u32,
window_width: u32,

atlas: Atlas,
grid: Grid,

allocator_adapter: *AllocatorAdapter,

pub const log = std.log.scoped(.renderer);

pub fn init(window: *Window, allocator: Allocator) !Backend {
    var self: Backend = undefined;
    try self.setup(window, allocator);
    return self;
}

pub fn setup(self: *Backend, window: *Window, allocator: Allocator) !void {
    self.allocator_adapter = try allocator.create(AllocatorAdapter);

    self.allocator_adapter.initInPlace(allocator);

    const surface_creation_info = SurfaceCreationInfo.fromWindow(window);

    // Instance and Device are temporary.
    // They are created only to initialize Context.
    // Context takes ownership and cleans them up.
    const instance = try Context.Instance.init(
        allocator,
        &self.allocator_adapter.alloc_callbacks,
        SurfaceCreationInfo.instanceExtensions(),
    );
    errdefer instance.deinit();

    const surface = try createWindowSurface(&instance, surface_creation_info);

    const device = try Context.Device.init(
        allocator,
        &instance,
        surface,
        SurfaceCreationInfo.deviceExtensions(),
    );
    errdefer device.deinit(&instance);

    self.context = try Context.init(allocator, instance, device);
    errdefer self.context.deinit(allocator);

    self.swapchain =
        try Swapchain.init(self.context, allocator, surface, .{
            .extent = .{
                .height = window.height,
                .width = window.width,
            },
        });

    self.target = try Target.initFromSwapchain(&self.swapchain, allocator);

    var render_pass_builder = RenderPass.Builder.init(allocator);
    defer render_pass_builder.deinit();

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
        .src_subpass = 0,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
    });

    self.render_pass = try render_pass_builder.build(self.context);

    const descriptor_pool = try DescriptorPool.Builder
        .addPoolSize(.storage_buffer, 2)
        .addPoolSize(.combined_image_sampler, 1)
        .addPoolSize(.uniform_buffer, 1)
        .build(self.context);

    defer descriptor_pool.deinit();

    const descriptor_set_layout = try DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .addBinding(2, .storage_buffer, 1, .{ .vertex_bit = true })
        .addBinding(3, .storage_buffer, 1, .{ .vertex_bit = true })
        .build(self.context);

    const descriptor_set = try descriptor_pool.allocDescriptorSets(&descriptor_set_layout);
    try descriptor_pool.freeDescriptorSet(descriptor_set);

    defer descriptor_set_layout.deinit(self.context);

    self.atlas = try Atlas.loadAll(allocator, 22, 15, 2000);
    errdefer self.atlas.deinit(allocator);

    const grid_rows = window.height / self.atlas.cell_height;
    const grid_cols = window.width / self.atlas.cell_width;

    self.grid = try Grid.create(allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });
    errdefer self.grid.free(allocator);
}

pub fn deinit(self: *Backend) void {
    const allocator = self.allocator_adapter.allocator;
    self.grid.free(allocator);
    self.atlas.deinit(allocator);

    self.context.vki.destroySurfaceKHR(
        self.context.instance,
        self.swapchain.surface,
        self.context.vk_allocator,
    );

    self.swapchain.deinit(allocator);
    self.render_pass.deinit();

    self.target.deinit(self.context, allocator);

    self.context.deinit(allocator);
    self.allocator_adapter.deinit();

    allocator.destroy(self.allocator_adapter);
}

pub fn clearBuffer(self: *Backend, color: ColorRGBAf32) void {
    _ = self;
    _ = color;
}

pub fn resize(self: *Backend, width: u32, height: u32) !void {
    const grid_rows = height / self.atlas.cell_height;
    const grid_cols = width / self.atlas.cell_width;

    try self.grid.resize(self.allocator_adapter.allocator, .{
        .rows = grid_rows,
        .cols = grid_cols,
    });

    try self.swapchain.recreate(
        self.allocator_adapter.allocator,
        .{ .width = width, .height = height },
    );

    self.target.deinit(
        self.context,
        self.allocator_adapter.allocator,
    );

    self.target = try Target.initFromSwapchain(
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
    _ = bg_color;
    _ = fg_color;

    const glyph_index = self.atlas.glyph_lookup_map.getIndex(char_code) orelse 0;

    try self.grid.set(.{
        .packed_pos = (col << 16) | row,
        .glyph_index = @intCast(glyph_index),
        .style_index = 0,
    });
}

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const os_tag = builtin.os.tag;
const vk = @import("vulkan");

const Context = @import("core/Context.zig");
const Swapchain = @import("core/Swapchain.zig");
const RenderPass = @import("core/RenderPass.zig");
const descriptor = @import("core/descriptor.zig");
const DescriptorPool = descriptor.DescriptorPool;
const DescriptorSetLayout = descriptor.DescriptorSetLayout;
const Target = @import("Target.zig");
const window_surface = @import("window_surface.zig");
const SurfaceCreationInfo = window_surface.SurfaceCreationInfo;
const createWindowSurface = window_surface.createWindowSurface;

const Window = @import("../../../window/root.zig").Window;
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("../../common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("../../common/color.zig").ColorRGBAf32;
const DynamicLibrary = @import("../../../DynamicLibrary.zig");
const AllocatorAdapter = @import("memory/AllocatorAdapter.zig");
const Grid = @import("../../../Grid.zig");
const Atlas = @import("../../../font/Atlas.zig");

const RenderPipeline = @This();

pipeline: core.Pipeline,
bg_pass_pipeline: core.Pipeline,
pipeline_layout: core.PipelineLayout,
renderpass: core.RenderPass,

pub const DisplayInfo = struct {
    image_attachemnt_format: vk.Format,
    extent: vk.Extent2D,
    final_layout: vk.ImageLayout = .present_src_khr,
};

pub const DescriptorSetInfo = struct {
    descriptor_set_layouts: []const core.DescriptorSetLayout,
};

pub fn init(
    allocator: std.mem.Allocator,
    device: *const core.Device,
    display_info: DisplayInfo,
    descriptor_info: DescriptorSetInfo,
) !RenderPipeline {
    const text_vert_asset = try AssetsManager.instance
        .get("shaders/text.vert.spv");
    const text_vert_data = try text_vert_asset.fixedBuffer();

    const text_vert_data_aligned = try allocator.alignedAlloc(u8, .@"8", text_vert_data.len);
    defer allocator.free(text_vert_data_aligned);

    @memcpy(text_vert_data_aligned, text_vert_data);

    const text_frag_asset = try AssetsManager.instance
        .get("shaders/text.frag.spv");
    const text_frag_data = try text_frag_asset.fixedBuffer();

    const text_frag_data_aligned = try allocator.alignedAlloc(u8, .@"8", text_frag_data.len);
    defer allocator.free(text_frag_data_aligned);

    @memcpy(text_frag_data_aligned, text_frag_data);

    const bg_vert_asset = try AssetsManager.instance
        .get("shaders/background.vert.spv");
    const bg_vert_data = try bg_vert_asset.fixedBuffer();

    const bg_vert_data_aligned = try allocator.alignedAlloc(u8, .@"8", bg_vert_data.len);
    defer allocator.free(bg_vert_data_aligned);

    @memcpy(bg_vert_data_aligned, bg_vert_data);

    const bg_frag_asset = try AssetsManager.instance
        .get("shaders/background.frag.spv");
    const bg_frag_data = try bg_frag_asset.fixedBuffer();

    const bg_frag_data_aligned = try allocator.alignedAlloc(u8, .@"8", bg_frag_data.len);
    defer allocator.free(bg_frag_data_aligned);

    @memcpy(bg_frag_data_aligned, bg_frag_data);

    var vertex_shader = core.ShaderModule.init(
        @alignCast(text_vert_data_aligned),
        "main",
        .vertex,
    );
    defer vertex_shader.deinit(device);

    var fragment_shader = core.ShaderModule.init(
        @alignCast(text_frag_data_aligned),
        "main",
        .fragment,
    );

    defer fragment_shader.deinit(device);

    var bg_vertex_shader = core.ShaderModule.init(
        @alignCast(bg_vert_data_aligned),
        "main",
        .vertex,
    );
    defer bg_vertex_shader.deinit(device);

    var bg_fragment_shader = core.ShaderModule.init(
        @alignCast(bg_frag_data_aligned),
        "main",
        .fragment,
    );
    defer bg_fragment_shader.deinit(device);

    var renderpass_builder = core.RenderPass.Builder.init(allocator);
    defer renderpass_builder.deinit();

    try renderpass_builder.addAttachment(.{
        .format = display_info.image_attachemnt_format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = display_info.final_layout,
    });

    try renderpass_builder.addSubpass(.{
        .pipeline_bind_point = .graphics,
        .color_attachments = &.{
            .{ .attachment = 0, .layout = .color_attachment_optimal },
        },
    });

    try renderpass_builder.addDependency(.{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
    });

    const renderpass = try renderpass_builder.build(device);

    const pipeline_layout = try core.PipelineLayout.init(
        device,
        descriptor_info.descriptor_set_layouts,
        allocator,
    );
    errdefer pipeline_layout.deinit(device);

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(display_info.extent.width),
        .height = @floatFromInt(display_info.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = display_info.extent,
    };

    const blend_attachment = vk.PipelineColorBlendAttachmentState{
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
    };

    var bg_pass_pipeline_builder = core.Pipeline.Builder.init(device, allocator);
    defer bg_pass_pipeline_builder.deinit();

    bg_pass_pipeline_builder.setLayout(&pipeline_layout);
    bg_pass_pipeline_builder.setRenderPass(&renderpass);

    try bg_pass_pipeline_builder.setVertexInput(&.{}, &.{});

    try bg_pass_pipeline_builder.addShader(&bg_vertex_shader);
    try bg_pass_pipeline_builder.addShader(&bg_fragment_shader);

    bg_pass_pipeline_builder.setViewport(viewport);
    bg_pass_pipeline_builder.setScissor(scissor);

    try bg_pass_pipeline_builder.addDynamicState(.viewport);
    try bg_pass_pipeline_builder.addDynamicState(.scissor);

    try bg_pass_pipeline_builder.addColorBlendAttachment(blend_attachment);

    const bg_pass_pipeline = try bg_pass_pipeline_builder.build();

    var pipeline_builder = core.Pipeline.Builder.init(device, allocator);
    defer pipeline_builder.deinit();

    pipeline_builder.setLayout(&pipeline_layout);
    pipeline_builder.setRenderPass(&renderpass);

    try pipeline_builder.setVertexInput(vertex_input.bindings, vertex_input.attributes);

    try pipeline_builder.addShader(&vertex_shader);
    try pipeline_builder.addShader(&fragment_shader);

    pipeline_builder.setViewport(viewport);
    pipeline_builder.setScissor(scissor);

    try pipeline_builder.addDynamicState(.viewport);
    try pipeline_builder.addDynamicState(.scissor);

    try pipeline_builder.addColorBlendAttachment(blend_attachment);

    const pipeline = try pipeline_builder.build();

    return .{
        .pipeline = pipeline,
        .bg_pass_pipeline = bg_pass_pipeline,
        .pipeline_layout = pipeline_layout,
        .renderpass = renderpass,
    };
}

pub fn deinit(self: *RenderPipeline, device: *const core.Device, allocator: std.mem.Allocator) void {
    self.pipeline.deinit();
    self.bg_pass_pipeline.deinit();
    self.pipeline_layout.deinit(device);
    self.renderpass.deinit(allocator);
}

const std = @import("std");
const vk = @import("vulkan");
const zerotty = @import("zerotty");
const AssetsManager = zerotty.AssetsManager;

const core = @import("../core/root.zig");

const vertex = @import("../../root.zig").vertex;

const vertex_input = core.Pipeline.VertexInputDescriptionBuilder
    .addBinding(.{ .binding = 0, .stride = @sizeOf(vertex.TextInstance), .input_rate = .instance })
    .addAttribute(.{ .location = 0, .binding = 0, .format = .r32_uint, .offset = @offsetOf(vertex.TextInstance, "p_postion") })
    .addAttribute(.{ .location = 1, .binding = 0, .format = .r32g32_uint, .offset = @offsetOf(vertex.TextInstance, "p_glyph_entry") })
    .addAttribute(.{ .location = 2, .binding = 0, .format = .r8g8b8a8_unorm, .offset = @offsetOf(vertex.TextInstance, "fg_color") })
    .addAttribute(.{ .location = 3, .binding = 0, .format = .r8g8b8a8_unorm, .offset = @offsetOf(vertex.TextInstance, "bg_color") })
    .collect();

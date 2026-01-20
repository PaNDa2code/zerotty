const RenderPipeline = @This();

pipeline: core.Pipeline,
pipeline_layout: core.PipelineLayout,
renderpass: core.RenderPass,

pub const DisplayInfo = struct {
    image_attachemnt_format: vk.Format,
    extent: vk.Extent2D,
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
    var vertex_shader = core.ShaderModule.init(
        &assets.shaders.cell_vert,
        "main",
        .vertex,
    );
    defer vertex_shader.deinit(device);

    var fragment_shader = core.ShaderModule.init(
        &assets.shaders.cell_frag,
        "main",
        .fragment,
    );

    defer fragment_shader.deinit(device);

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
        .final_layout = .present_src_khr,
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

    var pipeline_builder = core.Pipeline.Builder.init(device, allocator);
    defer pipeline_builder.deinit();

    const pipeline_layout = try core.PipelineLayout.init(
        device,
        descriptor_info.descriptor_set_layouts,
        allocator,
    );
    errdefer pipeline_layout.deinit(device);

    pipeline_builder.setLayout(&pipeline_layout);
    pipeline_builder.setRenderPass(&renderpass);

    try pipeline_builder.setVertexInput(vertex_input.bindings, vertex_input.attributes);

    try pipeline_builder.addShader(&vertex_shader);
    try pipeline_builder.addShader(&fragment_shader);

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

    return .{
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
        .renderpass = renderpass,
    };
}

pub fn deinit(self: *RenderPipeline, device: *const core.Device, allocator: std.mem.Allocator) void {
    self.pipeline.deinit();
    self.pipeline_layout.deinit(device);
    self.renderpass.deinit(allocator);
}

const std = @import("std");
const vk = @import("vulkan");
const assets = @import("assets");

const core = @import("../core/root.zig");

const vertex = @import("vertex.zig");

const vertex_input = core.Pipeline.VertexInputDescriptionBuilder
    .addBinding(.{ .binding = 0, .stride = @sizeOf(vertex.Instance), .input_rate = .instance })
    .addAttribute(.{ .location = 1, .binding = 0, .format = .r32_uint, .offset = @offsetOf(vertex.Instance, "packed_pos") })
    .addAttribute(.{ .location = 2, .binding = 0, .format = .r32_uint, .offset = @offsetOf(vertex.Instance, "glyph_index") })
    .addAttribute(.{ .location = 3, .binding = 0, .format = .r32_uint, .offset = @offsetOf(vertex.Instance, "style_index") })
    .collect();

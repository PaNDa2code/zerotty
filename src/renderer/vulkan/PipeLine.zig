const PipeLine = @This();

graphics_pipeline: vk.Pipeline = .null_handle,
pipeline_layout: vk.PipelineLayout = .null_handle,
vertex_shader_module: vk.ShaderModule = .null_handle,
fragment_shader_module: vk.ShaderModule = .null_handle,

layout: vk.PipelineLayout = .null_handle,
handle: vk.Pipeline = .null_handle,

renderer_pass: vk.RenderPass = .null_handle,
subpass_index: u32 = 0,

const vert_shader_spv = &assets.shaders.cell_vert;
const frag_shader_spv = &assets.shaders.cell_frag;

pub fn init(
    vkd: *const vk.DeviceWrapper,
    dev: vk.Device,
    vkmemcb: *const vk.AllocationCallbacks,
    swap_chain_extent: vk.Extent2D,
) !PipeLine {
    if (dev == .null_handle)
        return error.InvalidArgument;

    const vertex_shader_module = try shader_utils.compileSpirv(vert_shader_spv, dev, vkd, vkmemcb);
    const fragment_shader_module = try shader_utils.compileSpirv(frag_shader_spv, dev, vkd, vkmemcb);

    const vert_shader_creation_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .vertex_bit = true },
        .module = vertex_shader_module,
        .p_name = "main",
    };

    const frag_shader_creation_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .fragment_bit = true },
        .module = fragment_shader_module,
        .p_name = "main",
    };

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ vert_shader_creation_info, frag_shader_creation_info };

    const dynamic_stats = [_]vk.DynamicState{ .viewport, .scissor };

    const dynamic_stats_create_info: vk.PipelineDynamicStateCreateInfo = .{
        .dynamic_state_count = dynamic_stats.len,
        .p_dynamic_states = &dynamic_stats,
    };

    const vertex_input_info: vk.PipelineVertexInputStateCreateInfo = .{};

    const input_assembly_info: vk.PipelineInputAssemblyStateCreateInfo = .{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swap_chain_extent.width),
        .height = @floatFromInt(swap_chain_extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swap_chain_extent,
    };

    const viewport_state_create_info: vk.PipelineViewportStateCreateInfo = .{
        .scissor_count = 1,
        .p_scissors = &.{scissor},
        .viewport_count = 1,
        .p_viewports = &.{viewport},
    };

    const rasterizer_state_create_info: vk.PipelineRasterizationStateCreateInfo = .{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .line_width = 1,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
    };

    const multisampling: vk.PipelineMultisampleStateCreateInfo = .{
        .sample_shading_enable = 0,
        .rasterization_samples = .{ .@"1_bit" = true },
        .flags = .{},
        .min_sample_shading = 0,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const color_blend_attachment: vk.PipelineColorBlendAttachmentState = .{
        .blend_enable = vk.FALSE,
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

    const color_blend_state: vk.PipelineColorBlendStateCreateInfo = .{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &.{color_blend_attachment},
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    // Create an empty pipeline layout
    var pipeline_layout_info: vk.PipelineLayoutCreateInfo = .{
        .set_layout_count = 0,
        .p_set_layouts = null,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    const pipeline_layout = try vkd.createPipelineLayout(dev, &pipeline_layout_info, vkmemcb);

    // Fill graphics pipeline create info
    const pipeline_info: vk.GraphicsPipelineCreateInfo = .{
        .stage_count = shader_stages.len,
        .p_stages = &shader_stages,
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly_info,
        .p_viewport_state = &viewport_state_create_info,
        .p_rasterization_state = &rasterizer_state_create_info,
        .p_multisample_state = &multisampling,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_state,
        .p_dynamic_state = &dynamic_stats_create_info,
        .layout = pipeline_layout,
        // .render_pass = self.renderer_pass, // Make sure you set this before calling init
        .subpass = 0, //self.subpass_index,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var graphics_pipeline: vk.Pipeline = undefined;

    const res = try vkd.createGraphicsPipelines(dev, .null_handle, 1, &.{pipeline_info}, vkmemcb, @ptrCast(&graphics_pipeline));

    switch (res) {
        .success => {},
        else => @panic("creating vulkan pipeline didn't succeed"),
    }

    // return .{
    //     .vertex_shader_module = vertex_shader_module,
    //     .fragment_shader_module = fragment_shader_module,
    //     .layout = pipeline_layout,
    //     .handle = graphics_pipeline,
    //     // .renderer_pass = self.renderer_pass,
    //     // .subpass_index = self.subpass_index,
    // };

    return .{
        .graphics_pipeline = graphics_pipeline,
        .pipeline_layout = pipeline_layout,
        .vertex_shader_module = vertex_shader_module,
        .fragment_shader_module = fragment_shader_module,
    };
}

pub fn deinit(
    self: *PipeLine,
    vkd: *const vk.DeviceWrapper,
    dev: vk.Device,
    vkmemcb: *const vk.AllocationCallbacks,
) void {
    vkd.destroyPipelineLayout(dev, self.pipeline_layout, vkmemcb);
    vkd.destroyShaderModule(dev, self.vertex_shader_module, vkmemcb);
    vkd.destroyShaderModule(dev, self.fragment_shader_module, vkmemcb);
}

const std = @import("std");
const vk = @import("vulkan");
const assets = @import("assets");
const shader_utils = @import("shader_utils.zig");

const Pipeline = @This();

const std = @import("std");
const vk = @import("vulkan");
const math = @import("../../common/math.zig");
const helper = @import("helpers/root.zig");
const assets = @import("assets");

const Core = @import("Core.zig");
const Descriptor = @import("Descriptor.zig");
const SwapChain = @import("SwapChain.zig");
const Atlas = @import("../../../font/Atlas.zig");
const Grid = @import("../../../Grid.zig");
const Cell = Grid.Cell;

const Vec4 = math.Vec4;

render_pass: vk.RenderPass,

handle: vk.Pipeline,
layout: vk.PipelineLayout,

frame_buffers: []vk.Framebuffer,

const vert_shader_spv = &assets.shaders.cell_vert;
const frag_shader_spv = &assets.shaders.cell_frag;

pub fn init(
    core: *const Core,
    swap_chain: *const SwapChain,
    descriptor: *const Descriptor,
) !Pipeline {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const color_attachment = vk.AttachmentDescription{
        .format = swap_chain.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass_discription = vk.SubpassDescription{
        .color_attachment_count = 1,
        .p_color_attachments = &.{color_attachment_ref},
        .pipeline_bind_point = .graphics,
    };

    const dependancy = vk.SubpassDependency{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
    };

    const render_pass_create_info = vk.RenderPassCreateInfo{
        .attachment_count = 1,
        .p_attachments = &.{color_attachment},
        .subpass_count = 1,
        .p_subpasses = &.{subpass_discription},
        .dependency_count = 1,
        .p_dependencies = &.{dependancy},
    };

    const render_pass = try vkd.createRenderPass(
        core.device,
        &render_pass_create_info,
        &alloc_callbacks,
    );

    const vertex_shader_module = try helper.shader.compileSpirv(
        vert_shader_spv,
        core.device,
        vkd,
        &alloc_callbacks,
    );
    defer vkd.destroyShaderModule(
        core.device,
        vertex_shader_module,
        &alloc_callbacks,
    );

    const fragment_shader_module = try helper.shader.compileSpirv(
        frag_shader_spv,
        core.device,
        vkd,
        &alloc_callbacks,
    );
    defer vkd.destroyShaderModule(
        core.device,
        fragment_shader_module,
        &alloc_callbacks,
    );

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vertex_shader_module,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = fragment_shader_module,
            .p_name = "main",
        },
    };
    const dynamic_stats = [_]vk.DynamicState{ .viewport, .scissor };

    const dynamic_stats_create_info =
        vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = dynamic_stats.len,
            .p_dynamic_states = &dynamic_stats,
        };

    const vertex_input_info =
        vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = vertex_binding.len,
            .p_vertex_binding_descriptions = &vertex_binding,
            .vertex_attribute_description_count = vertex_attributes.len,
            .p_vertex_attribute_descriptions = &vertex_attributes,
        };

    const input_assembly_info =
        vk.PipelineInputAssemblyStateCreateInfo{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

    const viewport: vk.Viewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swap_chain.extent.width),
        .height = @floatFromInt(swap_chain.extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor: vk.Rect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swap_chain.extent,
    };

    const viewport_state_info =
        vk.PipelineViewportStateCreateInfo{
            .scissor_count = 1,
            .p_scissors = &.{scissor},
            .viewport_count = 1,
            .p_viewports = &.{viewport},
        };

    const rasterizer_state_info =
        vk.PipelineRasterizationStateCreateInfo{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

    const multisampling =
        vk.PipelineMultisampleStateCreateInfo{
            .sample_shading_enable = .false,
            .rasterization_samples = .{ .@"1_bit" = true },
            .flags = .{},
            .min_sample_shading = 0,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

    const color_blend_attachment =
        vk.PipelineColorBlendAttachmentState{
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

    const color_blend_state =
        vk.PipelineColorBlendStateCreateInfo{
            .logic_op_enable = .false,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{color_blend_attachment},
            .blend_constants = .{ 0, 0, 0, 0 },
        };

    const pipeline_layout_info =
        vk.PipelineLayoutCreateInfo{
            .set_layout_count = 1,
            .p_set_layouts = &.{descriptor.layout},
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        };

    const layout = try vkd.createPipelineLayout(
        core.device,
        &pipeline_layout_info,
        &alloc_callbacks,
    );

    const pipeline_info =
        vk.GraphicsPipelineCreateInfo{
            .stage_count = shader_stages.len,
            .p_stages = &shader_stages,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &input_assembly_info,
            .p_viewport_state = &viewport_state_info,
            .p_rasterization_state = &rasterizer_state_info,
            .p_multisample_state = &multisampling,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &color_blend_state,
            .p_dynamic_state = &dynamic_stats_create_info,
            .layout = layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

    var pipeline: vk.Pipeline = undefined;

    const res = try vkd.createGraphicsPipelines(
        core.device,
        .null_handle,
        1,
        &.{pipeline_info},
        &alloc_callbacks,
        @ptrCast(&pipeline),
    );
    switch (res) {
        .success => {},
        else => return error.Unknown,
    }

    const frame_buffers_count = swap_chain.image_views.len;

    const frame_buffers =
        try core.vk_mem.allocator.alloc(
            vk.Framebuffer,
            frame_buffers_count,
        );

    for (0..frame_buffers_count) |i| {
        const frame_buffer_create_info = vk.FramebufferCreateInfo{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = &.{swap_chain.image_views[i]},
            .width = swap_chain.extent.width,
            .height = swap_chain.extent.height,
            .layers = 1,
        };

        frame_buffers[i] =
            try vkd.createFramebuffer(
                core.device,
                &frame_buffer_create_info,
                &alloc_callbacks,
            );
    }

    return .{
        .handle = pipeline,
        .layout = layout,
        .render_pass = render_pass,
        .frame_buffers = frame_buffers,
    };
}

pub fn deinit(self: *const Pipeline, core: *const Core) void {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    for (self.frame_buffers) |buffer| {
        vkd.destroyFramebuffer(core.device, buffer, &alloc_callbacks);
    }
    core.vk_mem.allocator.free(self.frame_buffers);

    vkd.destroyPipeline(core.device, self.handle, &alloc_callbacks);
    vkd.destroyRenderPass(core.device, self.render_pass, &alloc_callbacks);
    vkd.destroyPipelineLayout(core.device, self.layout, &alloc_callbacks);
}

pub fn recreateFrameBuffers(
    self: *Pipeline,
    core: *const Core,
    swap_chain: *const SwapChain,
) !void {
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const frame_buffers = self.frame_buffers;

    for (0..frame_buffers.len) |i| {
        core.dispatch.vkd.destroyFramebuffer(
            core.device,
            frame_buffers[i],
            &alloc_callbacks,
        );

        const frame_buffer_create_info = vk.FramebufferCreateInfo{
            .render_pass = self.render_pass,
            .attachment_count = 1,
            .p_attachments = &.{swap_chain.image_views[i]},
            .width = swap_chain.extent.width,
            .height = swap_chain.extent.height,
            .layers = 1,
        };

        frame_buffers[i] =
            try core.dispatch.vkd.createFramebuffer(
                core.device,
                &frame_buffer_create_info,
                &alloc_callbacks,
            );
    }
}

const vertex_binding = [_]vk.VertexInputBindingDescription{
    .{ .binding = 0, .stride = @sizeOf(Cell), .input_rate = .instance },
};

const vertex_attributes = [_]vk.VertexInputAttributeDescription{
    .{ .location = 1, .binding = 0, .format = .r32_uint, .offset = @offsetOf(Cell, "packed_pos") },
    .{ .location = 2, .binding = 0, .format = .r32_uint, .offset = @offsetOf(Cell, "glyph_index") },
    .{ .location = 3, .binding = 0, .format = .r32_uint, .offset = @offsetOf(Cell, "style_index") },
};

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const assets = @import("assets");
const shader_utils = @import("shader_utils.zig");

const VulkanRenderer = @import("Vulkan.zig");

const vert_shader_spv = &assets.shaders.cell_vert;
const frag_shader_spv = &assets.shaders.cell_frag;

const vertex_binding = getVertexBindingDescription();
const vertex_attributes = getVertexAttributeDescriptions();

pub fn createPipeLine(self: *VulkanRenderer) !void {
    self.pipe_line = try _createPipeLine(
        self.instance_wrapper,
        self.device_wrapper,
        self.device,
        self.physical_device,
        &self.pipe_line_layout,
        self.render_pass,
        self.swap_chain_extent,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn _createPipeLine(
    vki: *const vk.InstanceWrapper,
    vkd: *const vk.DeviceWrapper,
    dev: vk.Device,
    physical_device: vk.PhysicalDevice,
    p_pipe_line_layout: *vk.PipelineLayout,
    render_pass: vk.RenderPass,
    swap_chain_extent: vk.Extent2D,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.Pipeline {
    const vertex_shader_module = try shader_utils.compileSpirv(vert_shader_spv, dev, vkd, vkmemcb);
    defer vkd.destroyShaderModule(dev, vertex_shader_module, vkmemcb);

    const vert_shader_creation_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .vertex_bit = true },
        .module = vertex_shader_module,
        .p_name = "main",
    };

    const fragment_shader_module = try shader_utils.compileSpirv(frag_shader_spv, dev, vkd, vkmemcb);
    defer vkd.destroyShaderModule(dev, fragment_shader_module, vkmemcb);

    const frag_shader_creation_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .fragment_bit = true },
        .module = fragment_shader_module,
        .p_name = "main",
    };

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        vert_shader_creation_info,
        frag_shader_creation_info,
    };

    const dynamic_stats = [_]vk.DynamicState{ .viewport, .scissor };

    const dynamic_stats_create_info: vk.PipelineDynamicStateCreateInfo = .{
        .dynamic_state_count = dynamic_stats.len,
        .p_dynamic_states = &dynamic_stats,
    };

    _ = try createUniformBuffer(vki, vkd, dev, physical_device, vkmemcb);

    const bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_type = .combined_image_sampler,
            .descriptor_count = 1,
            .stage_flags = .{ .fragment_bit = true },
        },
    };

    const descriptor_set_layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = bindings.len,
        .p_bindings = &bindings,
    };

    const descriptor_set_layout = try vkd.createDescriptorSetLayout(dev, &descriptor_set_layout_info, vkmemcb);

    const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = &.{vertex_binding},
        .vertex_attribute_description_count = vertex_attributes.len,
        .p_vertex_attribute_descriptions = vertex_attributes.ptr,
    };

    const input_assembly_info: vk.PipelineInputAssemblyStateCreateInfo = .{
        .topology = .triangle_list,
        .primitive_restart_enable = .false,
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

    const multisampling: vk.PipelineMultisampleStateCreateInfo = .{
        .sample_shading_enable = .false,
        .rasterization_samples = .{ .@"1_bit" = true },
        .flags = .{},
        .min_sample_shading = 0,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };

    const color_blend_attachment: vk.PipelineColorBlendAttachmentState = .{
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

    const color_blend_state: vk.PipelineColorBlendStateCreateInfo = .{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &.{color_blend_attachment},
        .blend_constants = .{ 0, 0, 0, 0 },
    };

    const pipeline_layout_info: vk.PipelineLayoutCreateInfo = .{
        .set_layout_count = 1,
        .p_set_layouts = &.{descriptor_set_layout},
        .push_constant_range_count = 0,
        .p_push_constant_ranges = null,
    };

    const pipeline_layout = try vkd.createPipelineLayout(dev, &pipeline_layout_info, vkmemcb);

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
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var graphics_pipeline: vk.Pipeline = undefined;

    const res = try vkd.createGraphicsPipelines(
        dev,
        .null_handle,
        1,
        &.{pipeline_info},
        vkmemcb,
        @ptrCast(&graphics_pipeline),
    );
    switch (res) {
        .success => {},
        else => @panic("creating vulkan pipeline didn't succeed"),
    }

    p_pipe_line_layout.* = pipeline_layout;

    return graphics_pipeline;
}

fn createUniformBuffer(
    vki: *const vk.InstanceWrapper,
    vkd: *const vk.DeviceWrapper,
    dev: vk.Device,
    physical_device: vk.PhysicalDevice,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.Buffer {
    const buffer_info = vk.BufferCreateInfo{
        .size = @sizeOf(UniformsBlock),
        .usage = .{ .uniform_buffer_bit = true },
        .sharing_mode = .exclusive,
    };

    const buffer = try vkd.createBuffer(dev, &buffer_info, vkmemcb);

    const mem_req = vkd.getBufferMemoryRequirements(dev, buffer);

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_req.size,
        .memory_type_index = findMemoryType(vki, physical_device, mem_req.memory_type_bits, .{}),
    };

    const buffer_memory = try vkd.allocateMemory(dev, &alloc_info, vkmemcb);

    try vkd.bindBufferMemory(dev, buffer, buffer_memory, 0);

    return buffer;
}

fn getVertexBindingDescription() vk.VertexInputBindingDescription {
    return .{
        .binding = 0,
        .stride = @sizeOf(Cell),
        .input_rate = .vertex,
    };
}

fn getVertexAttributeDescriptions() []const vk.VertexInputAttributeDescription {
    const descriptions = comptime [_]vk.VertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = .r32g32b32a32_sfloat, .offset = @sizeOf(Vec4(f32)) },
        .{ .location = 1, .binding = 0, .format = .r32_uint, .offset = @sizeOf(u32) },
        .{ .location = 2, .binding = 0, .format = .r32_uint, .offset = @sizeOf(u32) },
        .{ .location = 3, .binding = 0, .format = .r32_uint, .offset = @sizeOf(u32) },
        .{ .location = 4, .binding = 0, .format = .r32g32b32a32_sfloat, .offset = @sizeOf(Vec4(f32)) },
        .{ .location = 5, .binding = 0, .format = .r32g32b32a32_sfloat, .offset = @sizeOf(Vec4(f32)) },
        .{ .location = 6, .binding = 0, .format = .r32g32_uint, .offset = @sizeOf(Vec4(u32)) },
        .{ .location = 7, .binding = 0, .format = .r32g32_uint, .offset = @sizeOf(Vec4(u32)) },
        .{ .location = 8, .binding = 0, .format = .r32g32_sint, .offset = @sizeOf(Vec4(i32)) },
    };

    return descriptions[0..];
}

fn findMemoryType(
    vki: *const vk.InstanceWrapper,
    physical_device: vk.PhysicalDevice,
    typeFilter: u32,
    properties: vk.MemoryPropertyFlags,
) u32 {
    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(physical_device);

    var i: u32 = 0;
    while (i < mem_properties.memory_type_count) : (i += 1) {
        if ((typeFilter & (std.math.shr(u32, 1, i))) != 0 and
            mem_properties.memory_types[i].property_flags.contains(properties))
        {
            return i;
        }
    }
    @panic("Failed to find suitable memory type!");
}

const Cell = @import("../Grid.zig").Cell;

const math = @import("../math.zig");
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;

pub const UniformsBlock = packed struct {
    cell_height: f32,
    cell_width: f32,
    screen_height: f32,
    screen_width: f32,
    atlas_cols: f32,
    atlas_rows: f32,
    atlas_width: f32,
    atlas_height: f32,
    descender: f32,
};

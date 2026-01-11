const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const PipelineLayout = @import("PipelineLayout.zig");
const RenderPass = @import("RenderPass.zig");
const Framebuffer = @import("Framebuffer.zig");
const Shader = @import("../Shader.zig");

const Pipeline = @This();

device: *const Device,

handle: vk.Pipeline,
layout: vk.PipelineLayout,

pub const VertexInputDescriptionBuilder = VertexInputAssembler(&.{}, &.{});

fn VertexInputAssembler(
    comptime VertexBindings: []const vk.VertexInputBindingDescription,
    comptime VertexAttributes: []const vk.VertexInputAttributeDescription,
) type {
    return struct {
        const VertexInputDescription = struct {
            bindings: []const vk.VertexInputBindingDescription,
            attributes: []const vk.VertexInputAttributeDescription,
        };

        pub fn addBinding(binding: vk.VertexInputBindingDescription) type {
            return VertexInputAssembler(VertexBindings ++ [_]vk.VertexInputBindingDescription{binding}, VertexAttributes);
        }
        pub fn addAttribute(attr: vk.VertexInputAttributeDescription) type {
            return VertexInputAssembler(VertexBindings, VertexAttributes ++ [_]vk.VertexInputAttributeDescription{attr});
        }

        pub fn collect() VertexInputDescription {
            return .{
                .bindings = VertexBindings,
                .attributes = VertexAttributes,
            };
        }
    };
}

pub const Builder = struct {
    device: *const Device,
    allocator: std.mem.Allocator,

    shaders: std.ArrayList(vk.PipelineShaderStageCreateInfo),
    vertex_bindings: std.ArrayList(vk.VertexInputBindingDescription),
    vertex_attributes: std.ArrayList(vk.VertexInputAttributeDescription),

    input_assembly: vk.PipelineInputAssemblyStateCreateInfo,

    viewport: ?vk.Viewport = null,
    scissor: ?vk.Rect2D = null,

    rasterizer: vk.PipelineRasterizationStateCreateInfo,
    multisampling: vk.PipelineMultisampleStateCreateInfo,
    depth_stencil: ?vk.PipelineDepthStencilStateCreateInfo = null,

    color_blend_attachments: std.ArrayList(vk.PipelineColorBlendAttachmentState),
    color_blend_state: vk.PipelineColorBlendStateCreateInfo,

    dynamic_states: std.ArrayList(vk.DynamicState),

    layout: vk.PipelineLayout = .null_handle,
    render_pass: vk.RenderPass = .null_handle,
    subpass: u32 = 0,

    pub fn init(device: *const Device, allocator: std.mem.Allocator) Builder {
        return .{
            .device = device,
            .allocator = allocator,
            .shaders = .empty,
            .vertex_bindings = .empty,
            .vertex_attributes = .empty,
            .input_assembly = .{
                .topology = .triangle_list,
                .primitive_restart_enable = .false,
            },
            .rasterizer = .{
                .depth_clamp_enable = .false,
                .rasterizer_discard_enable = .false,
                .polygon_mode = .fill,
                .line_width = 1.0,
                .cull_mode = .{ .back_bit = true },
                .front_face = .clockwise,
                .depth_bias_enable = .false,
                .depth_bias_constant_factor = 0,
                .depth_bias_clamp = 0,
                .depth_bias_slope_factor = 0,
            },
            .multisampling = .{
                .sample_shading_enable = .false,
                .rasterization_samples = .{ .@"1_bit" = true },
                .flags = .{},
                .min_sample_shading = 0,
                .alpha_to_coverage_enable = .false,
                .alpha_to_one_enable = .false,
            },
            .color_blend_attachments = .empty,
            .color_blend_state = .{
                .logic_op_enable = .false,
                .logic_op = .copy,
                .attachment_count = 0,
                .p_attachments = undefined,
                .blend_constants = .{ 0, 0, 0, 0 },
            },
            .dynamic_states = .empty,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.shaders.deinit(self.allocator);
        self.vertex_bindings.deinit(self.allocator);
        self.vertex_attributes.deinit(self.allocator);
        self.color_blend_attachments.deinit(self.allocator);
        self.dynamic_states.deinit(self.allocator);
    }

    pub fn addShader(self: *Builder, shader: *Shader) !void {
        try self.shaders.append(self.allocator, try shader.pipelineStageInfo(self.device));
    }

    pub fn setVertexInput(self: *Builder, bindings: []const vk.VertexInputBindingDescription, attributes: []const vk.VertexInputAttributeDescription) !void {
        try self.vertex_bindings.appendSlice(self.allocator, bindings);
        try self.vertex_attributes.appendSlice(self.allocator, attributes);
    }

    pub fn setInputAssembly(self: *Builder, topology: vk.PrimitiveTopology) void {
        self.input_assembly.topology = topology;
    }

    pub fn setViewport(self: *Builder, viewport: vk.Viewport) void {
        self.viewport = viewport;
    }

    pub fn setScissor(self: *Builder, scissor: vk.Rect2D) void {
        self.scissor = scissor;
    }

    pub fn setRasterization(self: *Builder, info: vk.PipelineRasterizationStateCreateInfo) void {
        self.rasterizer = info;
    }

    pub fn setMultisampling(self: *Builder, info: vk.PipelineMultisampleStateCreateInfo) void {
        self.multisampling = info;
    }

    pub fn addColorBlendAttachment(self: *Builder, attachment: vk.PipelineColorBlendAttachmentState) !void {
        try self.color_blend_attachments.append(self.allocator, attachment);
    }

    pub fn setColorBlendState(self: *Builder, state: vk.PipelineColorBlendStateCreateInfo) void {
        self.color_blend_state = state;
    }

    pub fn addDynamicState(self: *Builder, state: vk.DynamicState) !void {
        try self.dynamic_states.append(self.allocator, state);
    }

    pub fn setLayout(self: *Builder, layout: *const PipelineLayout) void {
        self.layout = layout.handle;
    }

    pub fn setRenderPass(self: *Builder, render_pass: *const RenderPass) void {
        self.render_pass = render_pass.handle;
    }

    pub fn build(self: *Builder) !Pipeline {
        const vertex_input_info = vk.PipelineVertexInputStateCreateInfo{
            .vertex_binding_description_count = @intCast(self.vertex_bindings.items.len),
            .p_vertex_binding_descriptions = self.vertex_bindings.items.ptr,
            .vertex_attribute_description_count = @intCast(self.vertex_attributes.items.len),
            .p_vertex_attribute_descriptions = self.vertex_attributes.items.ptr,
        };

        var viewport_state = vk.PipelineViewportStateCreateInfo{
            .scissor_count = 1,
            .p_scissors = undefined,
            .viewport_count = 1,
            .p_viewports = undefined,
        };

        if (self.viewport) |*v| {
            viewport_state.p_viewports = @ptrCast(v);
        }

        if (self.scissor) |*s| {
            viewport_state.p_scissors = @ptrCast(s);
        }

        const dynamic_stats_create_info = vk.PipelineDynamicStateCreateInfo{
            .dynamic_state_count = @intCast(self.dynamic_states.items.len),
            .p_dynamic_states = self.dynamic_states.items.ptr,
        };

        self.color_blend_state.attachment_count = @intCast(self.color_blend_attachments.items.len);
        self.color_blend_state.p_attachments = self.color_blend_attachments.items.ptr;

        const pipeline_info = vk.GraphicsPipelineCreateInfo{
            .stage_count = @intCast(self.shaders.items.len),
            .p_stages = self.shaders.items.ptr,
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &self.input_assembly,
            .p_viewport_state = &viewport_state,
            .p_rasterization_state = &self.rasterizer,
            .p_multisample_state = &self.multisampling,
            .p_depth_stencil_state = if (self.depth_stencil) |*ds| ds else null,
            .p_color_blend_state = &self.color_blend_state,
            .p_dynamic_state = &dynamic_stats_create_info,
            .layout = self.layout,
            .render_pass = self.render_pass,
            .subpass = self.subpass,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var handle = vk.Pipeline.null_handle;

        _ = try self.device.vkd.createGraphicsPipelines(
            self.device.handle,
            .null_handle,
            1,
            @ptrCast(&pipeline_info),
            self.device.vk_allocator,
            @ptrCast(&handle),
        );

        return .{
            .device = self.device,
            .handle = handle,
            .layout = self.layout,
        };
    }
};

pub fn deinit(self: Pipeline) void {
    self.device.vkd.destroyPipeline(self.device.handle, self.handle, self.device.vk_allocator);
}

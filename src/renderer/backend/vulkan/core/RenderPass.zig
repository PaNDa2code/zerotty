const RenderPass = @This();

context: *const Context,

handle: vk.RenderPass,
color_format: vk.Format,

pub const InitError = vk.DeviceWrapper.CreateRenderPassError;

pub fn create(
    context: *const Context,
    color_format: vk.Format,
) InitError!RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = color_format,
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

    const subpass_description = vk.SubpassDescription{
        .color_attachment_count = 1,
        .p_color_attachments = &.{color_attachment_ref},
        .pipeline_bind_point = .graphics,
    };

    const dependency = vk.SubpassDependency{
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
        .p_subpasses = &.{subpass_description},
        .dependency_count = 1,
        .p_dependencies = &.{dependency},
    };

    const render_pass = try context.vkd.createRenderPass(
        context.device,
        &render_pass_create_info,
        context.vk_allocator,
    );

    return .{
        .context = context,
        .handle = render_pass,
        .color_format = color_format,
    };
}

pub fn deinit(self: *RenderPass, context: *const Context) void {
    context.vkd.destroyRenderPass(
        context.device,
        self.handle,
        context.vk_allocator,
    );
}

const std = @import("std");
const vk = @import("vulkan");
const Context = @import("Context.zig");

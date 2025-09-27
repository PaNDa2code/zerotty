const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const vk = @import("vulkan");

const VulkanRenderer = @import("Vulkan.zig");

pub fn createRenderPass(self: *VulkanRenderer) !void {
    self.render_pass = try _createRenaderPass(
        self.device_wrapper,
        self.device,
        self.swap_chain_format,
        &self.vk_mem.vkAllocatorCallbacks(),
    );
}

fn _createRenaderPass(
    vkd: *const vk.DeviceWrapper,
    device: vk.Device,
    swap_chain_format: vk.Format,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = swap_chain_format,
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
        device,
        &render_pass_create_info,
        vkmemcb,
    );

    return render_pass;
}

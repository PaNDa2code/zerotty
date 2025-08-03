const PipeLine = @This();

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
) !PipeLine {
    if (dev == .null_handle)
        return error.InvalidArgument;

    const vertex_shader_module = try shader_utils.compileSpirv(vert_shader_spv, dev, vkd, vkmemcb);
    const fragment_shader_module = try shader_utils.compileSpirv(frag_shader_spv, dev, vkd, vkmemcb);

    return .{
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
    vkd.destroyShaderModule(dev, self.vertex_shader_module, vkmemcb);
    vkd.destroyShaderModule(dev, self.fragment_shader_module, vkmemcb);
}

const vk = @import("vulkan");
const assets = @import("assets");
const shader_utils = @import("shader_utils.zig");

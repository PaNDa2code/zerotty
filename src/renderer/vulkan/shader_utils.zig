const vk = @import("vulkan");

pub fn compileSpirv(
    buff: []align(@alignOf(u32)) const u8,
    dev: vk.Device,
    vkd: *const vk.DeviceWrapper,
    vkmemcb: *const vk.AllocationCallbacks,
) !vk.ShaderModule {
    const create_module_info = vk.ShaderModuleCreateInfo{
        .code_size = buff.len,
        .p_code = @ptrCast(buff.ptr),
    };

    return vkd.createShaderModule(dev, &create_module_info, vkmemcb);
}

const ShaderModule = @This();

// comptime values
entry_name: [:0]const u8,
shader_type: ShaderType,
spirv: []align(4) const u8,

module: vk.ShaderModule,

pub const ShaderType = enum {
    vertex,
    fragment,

    pub fn flags(self: ShaderType) vk.ShaderStageFlags {
        return switch (self) {
            .vertex => .{ .vertex_bit = true },
            .fragment => .{ .fragment_bit = true },
        };
    }
};

pub fn init(
    spirv: []align(4) const u8,
    entry_name: [:0]const u8,
    shader_type: ShaderType,
) ShaderModule {
    return .{
        .entry_name = entry_name,
        .shader_type = shader_type,
        .spirv = spirv,

        .module = .null_handle,
    };
}

pub const CompileError = vk.DeviceWrapper.CreateShaderModuleError;

pub fn compile(
    self: *ShaderModule,
    device: *const Device,
) CompileError!void {
    const shader_mod_info = vk.ShaderModuleCreateInfo{
        .code_size = self.spirv.len,
        .p_code = @ptrCast(self.spirv.ptr),
    };
    self.module = try device.vkd.createShaderModule(
        device.handle,
        &shader_mod_info,
        device.vk_allocator,
    );
}

pub fn pipelineStageInfo(
    self: *ShaderModule,
    device: *const Device,
) CompileError!vk.PipelineShaderStageCreateInfo {
    if (self.module == .null_handle) {
        try self.compile(device);
    }

    return .{
        .module = self.module,
        .p_name = self.entry_name.ptr,
        .stage = self.shader_type.flags(),
    };
}

pub fn deinit(
    self: *ShaderModule,
    device: *const Device,
) void {
    if (self.module != .null_handle) {
        device.vkd.destroyShaderModule(
            device.handle,
            self.module,
            device.vk_allocator,
        );
        self.module = .null_handle;
    }
}

const vk = @import("vulkan");
const Device = @import("Device.zig");

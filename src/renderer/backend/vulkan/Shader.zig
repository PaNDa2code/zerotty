const Shader = @This();

// comptime values
entry_name: [:0]const u8,
shader_type: ShaderType,
spirv: []align(4) u8,

module: vk.ShaderModule,

pub const ShaderType = enum {
    vertex,
    fragment,
};

pub fn init(
    spirv: []align(4) u8,
    entry_name: [:0]const u8,
    shader_type: ShaderType,
) Shader {
    return .{
        .entry_name = entry_name,
        .shader_type = shader_type,
        .spirv = spirv,

        .module = .null_handle,
    };
}

pub const CompileError = vk.DeviceWrapper.CreateShaderModuleError;

pub fn compile(
    self: *Shader,
    context: *const Context,
) CompileError!void {
    const shader_mod_info = vk.ShaderModuleCreateInfo{
        .code_size = self.spirv.len,
        .p_code = @ptrCast(self.spirv.ptr),
    };
    self.module = try context.vkd.createShaderModule(
        context.device,
        &shader_mod_info,
        context.vk_allocator,
    );
}

pub fn pipelineStageInfo(
    self: *Shader,
    context: *const Context,
) CompileError!vk.PipelineShaderStageCreateInfo {
    if (self.module == .null_handle) {
        try self.compile(context);
    }

    return .{
        .module = self.module,
        .p_name = self.entry_name.ptr,
        .stage = switch (self.shader_type) {
            .vertex => .{ .vertex_bit = true },
            .fragment => .{ .fragment_bit = true },
        },
    };
}

pub fn deinit(self: *Shader, context: *const Context) void {
    if (self.module != .null_handle) {
        context.vkd.destroyShaderModule(
            context.device,
            self.module,
            context.vk_allocator,
        );
        self.module = .null_handle;
    }
}


const vk = @import("vulkan");

const Context = @import("core/Context.zig");

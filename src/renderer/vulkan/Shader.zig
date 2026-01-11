const Shader = @This();

// comptime values
entry_name: [:0]const u8,
shader_type: ShaderType,
spirv: []align(4) const u8,

module: vk.ShaderModule,
resources: []const Resource,

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

pub const Resource = struct {
    // Shader interface
    type: ResourceType,
    mode: ResourceMode,
    stages: vk.ShaderStageFlags,

    // Descriptor info
    set: u32 = 0,
    binding: u32 = 0,

    // Interface variables
    location: u32 = 0,
    input_attachment_index: u32 = 0,

    // Type info
    vec_size: u32 = 0,
    columns: u32 = 0,
    array_size: u32 = 0,

    // Layout
    offset: u32 = 0,
    size: u32 = 0,

    // Specialization
    constant_id: u32 = 0,

    qualifiers: ShaderResourceQualifiers = .{},

    pub const Builder = ResourceBuilder(&.{});

    fn ResourceBuilder(comptime Resources: []const Resource) type {
        return struct {
            pub fn add(
                res: Resource,
            ) type {
                return ResourceBuilder(Resources ++ [_]Resource{res});
            }

            pub fn collect() []const Resource {
                return Resources;
            }
        };
    }

    const ResourceType = enum {
        input,
        input_attachment,
        output,

        image,
        image_sampler,
        image_storage,
        sampler,

        buffer_uniform,
        buffer_storage,

        push_constant,
        specialization_constant,
    };

    const ResourceMode = enum {
        static,
        dynamic,
        update_after_bind,
    };

    const ShaderResourceQualifiers = packed struct {
        non_readable: bool = false,
        non_writable: bool = false,
    };
};

pub fn init(
    spirv: []align(4) const u8,
    entry_name: [:0]const u8,
    shader_type: ShaderType,
    resources: []const Resource,
) Shader {
    return .{
        .entry_name = entry_name,
        .shader_type = shader_type,
        .spirv = spirv,

        .module = .null_handle,
        .resources = resources,
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
        .stage = self.shader_type.flags(),
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
const Context = @import("../core/Context.zig");

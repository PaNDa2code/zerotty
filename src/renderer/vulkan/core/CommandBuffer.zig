const CommandBuffer = @This();

pool: *const CommandPool,

handle: vk.CommandBuffer,

level: vk.CommandBufferLevel,

// state
recording: bool = false,
in_render_pass: bool = false,

const StateError = error{
    NotRecording,
    StillRecording,
    InRenderPass,
    NotInRenderPass,
};

pub const InitError = CommandPool.AllocBufferError;

pub fn init(pool: *const CommandPool, level: vk.CommandBufferLevel) InitError!CommandBuffer {
    return pool.allocBuffer(level);
}

pub const BeginError = StateError ||
    vk.DeviceWrapper.BeginCommandBufferError;

pub fn begin(self: *CommandBuffer, flags: vk.CommandBufferUsageFlags) BeginError!void {
    if (self.recording)
        return error.StillRecording;

    const begin_info = vk.CommandBufferBeginInfo{ .flags = flags };

    try self.pool.device.vkd.beginCommandBuffer(self.handle, &begin_info);

    self.recording = true;
}

pub const BeginSecondaryError = StateError ||
    vk.DeviceWrapper.BeginCommandBufferError;

pub fn beginSecondary(
    self: *CommandBuffer,
    render_pass: ?*const RenderPass,
    framebuffer: ?Framebuffer,
    subpass: u32,
    usage_flags: vk.CommandBufferUsageFlags,
) BeginSecondaryError!void {
    if (self.recording)
        return error.StillRecording;

    var flags = usage_flags;
    var inheritance_info = std.mem.zeroInit(vk.CommandBufferInheritanceInfo, .{});

    if (render_pass) |rp| {
        flags = flags.merge(.{ .render_pass_continue_bit = true });

        inheritance_info = vk.CommandBufferInheritanceInfo{
            .render_pass = rp.handle,
            .subpass = subpass,
            .framebuffer = if (framebuffer) |fb| fb.handle else .null_handle,
            .occlusion_query_enable = .false,
        };
    }

    const begin_info = vk.CommandBufferBeginInfo{
        .flags = flags,
        .p_inheritance_info = &inheritance_info,
    };

    try self.pool.device.vkd.beginCommandBuffer(self.handle, &begin_info);

    self.recording = true;
}

pub const EndError = StateError ||
    vk.DeviceWrapper.EndCommandBufferError;

pub fn end(self: *CommandBuffer) EndError!void {
    if (!self.recording)
        return error.NotRecording;

    try self.pool.device.vkd.endCommandBuffer(self.handle);

    self.recording = false;
}

pub const ResetError = vk.DeviceWrapper.ResetCommandBufferError;

pub fn reset(self: *CommandBuffer, release_resources: bool) ResetError!void {
    try self.pool.device.vkd.resetCommandBuffer(
        self.handle,
        .{ .release_resources_bit = release_resources },
    );
}

pub const BeginRenderPassError = error{
    OperationNotAllowedOnSecondary,
} || StateError;

pub fn beginRenderPass(
    self: *CommandBuffer,
    render_pass: *const RenderPass,
    frame_buffer: Framebuffer,
    clear_values: ?[]vk.ClearValue,
    subpass_contents: vk.SubpassContents,
) BeginRenderPassError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.in_render_pass)
        return error.InRenderPass;

    if (self.level == .secondary)
        return error.OperationNotAllowedOnSecondary;

    var default_clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
    };

    const used_clear_values: []const vk.ClearValue =
        if (clear_values) |v|
            v
        else
            default_clear_values[0..];

    const render_pass_begin_info = vk.RenderPassBeginInfo{
        .render_pass = render_pass.handle,
        .framebuffer = frame_buffer.handle,
        .render_area = .{
            .extent = frame_buffer.extent,
            .offset = .{ .x = 0, .y = 0 },
        },
        .clear_value_count = @intCast(used_clear_values.len),
        .p_clear_values = used_clear_values.ptr,
    };

    self.pool.device.vkd.cmdBeginRenderPass(
        self.handle,
        &render_pass_begin_info,
        subpass_contents,
    );

    self.in_render_pass = true;
}

pub const EndRenderPassError = StateError;

pub fn endRenderPass(self: *CommandBuffer) !void {
    if (!self.recording)
        return error.NotRecording;
    if (!self.in_render_pass)
        return error.NotInRenderPass;

    self.pool.device.vkd.cmdEndRenderPass(self.handle);

    self.in_render_pass = false;
}

pub const BindPipelineError = StateError;

pub fn bindPipeline(self: *CommandBuffer, pipeline: vk.Pipeline, bind_point: vk.PipelineBindPoint) BindPipelineError!void {
    if (!self.recording)
        return error.NotRecording;
    if (!self.in_render_pass)
        return error.NotInRenderPass;

    self.pool.device.vkd.cmdBindPipeline(self.handle, bind_point, pipeline);
}

pub const CopyBufferError = StateError;

pub fn copyBuffer(self: *const CommandBuffer, src: vk.Buffer, dst: vk.Buffer, regons: []vk.BufferCopy) CopyBufferError!void {
    if (!self.recording)
        return error.NotRecording;

    if (regons.len == 0) return;

    self.pool.device.vkd.cmdCopyBuffer(
        self.handle,
        src,
        dst,
        @intCast(regons.len),
        regons.ptr,
    );
}

pub const ExecuteCommandsError = error{
    OperationNotAllowedOnSecondary,
} || StateError;

pub fn executeCommands(self: *const CommandBuffer, cmds: []vk.CommandBuffer) ExecuteCommandsError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.level == .secondary)
        return error.OperationNotAllowedOnSecondary;

    if (cmds.len == 0) return;

    self.pool.device.vkd.cmdExecuteCommands(self.handle, @intCast(cmds.len), cmds.ptr);
}

pub fn executeCommand(self: *const CommandBuffer, cmd: vk.CommandBuffer) ExecuteCommandsError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.level == .secondary)
        return error.OperationNotAllowedOnSecondary;

    self.pool.device.vkd.cmdExecuteCommands(self.handle, 1, @ptrCast(&cmd));
}

const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");
const CommandPool = @import("CommandPool.zig");
const RenderPass = @import("RenderPass.zig");
const Framebuffer = @import("Framebuffer.zig");

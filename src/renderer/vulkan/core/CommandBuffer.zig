const CommandBuffer = @This();

device: *const Device,

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

    try self.device.vkd.beginCommandBuffer(self.handle, &begin_info);

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
    var inheritance_info: vk.CommandBufferInheritanceInfo = undefined;

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
        .p_inheritance_info = if (render_pass != null) &inheritance_info else null,
    };

    try self.device.vkd.beginCommandBuffer(self.handle, &begin_info);

    self.recording = true;
}

pub const EndError = StateError ||
    vk.DeviceWrapper.EndCommandBufferError;

pub fn end(self: *CommandBuffer) EndError!void {
    if (!self.recording)
        return error.NotRecording;

    try self.device.vkd.endCommandBuffer(self.handle);

    self.recording = false;
}

pub const ResetError = vk.DeviceWrapper.ResetCommandBufferError;

pub fn reset(self: *CommandBuffer, release_resources: bool) ResetError!void {
    try self.device.vkd.resetCommandBuffer(
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
    clear_values: ?[]const vk.ClearValue,
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

    self.device.vkd.cmdBeginRenderPass(
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

    self.device.vkd.cmdEndRenderPass(self.handle);

    self.in_render_pass = false;
}

pub const BindPipelineError = StateError;

pub fn bindPipeline(self: *CommandBuffer, pipeline: vk.Pipeline, bind_point: vk.PipelineBindPoint) BindPipelineError!void {
    if (!self.recording)
        return error.NotRecording;

    self.device.vkd.cmdBindPipeline(self.handle, bind_point, pipeline);
}

pub const BindVertexBufferError = StateError;

pub fn bindVertexBuffer(self: *CommandBuffer, buffer: *const Buffer, offset: u64) BindPipelineError!void {
    if (!self.recording)
        return error.NotRecording;

    self.device.vkd.cmdBindVertexBuffers(
        self.handle,
        0,
        1,
        &.{buffer.handle},
        &.{offset},
    );
}

pub fn bindDescriptorSet(self: *CommandBuffer, set: *core.DescriptorSet, pipeline_layout: vk.PipelineLayout) !void {
    self.device.vkd.cmdBindDescriptorSets(
        self.handle,
        .graphics,
        pipeline_layout,
        0,
        1,
        &.{set.handle},
        0,
        null,
    );
}

pub const CopyBufferError = StateError;

pub fn copyBuffer(self: *const CommandBuffer, src: vk.Buffer, dst: vk.Buffer, regons: []vk.BufferCopy) CopyBufferError!void {
    if (!self.recording)
        return error.NotRecording;

    if (regons.len == 0) return;

    self.device.vkd.cmdCopyBuffer(
        self.handle,
        src,
        dst,
        @intCast(regons.len),
        regons.ptr,
    );
}

pub const CopyBufferToImageError = StateError;

pub fn copyBufferToImage(self: *const CommandBuffer, src: vk.Buffer, dst: vk.Image, dst_layout: vk.ImageLayout, regons: []const vk.BufferImageCopy) CopyBufferError!void {
    if (!self.recording)
        return error.NotRecording;

    if (regons.len == 0) return;

    self.device.vkd.cmdCopyBufferToImage(
        self.handle,
        src,
        dst,
        dst_layout,
        @intCast(regons.len),
        regons.ptr,
    );
}

pub const PipelineBarrierInfo = struct {
    src_stage_mask: vk.PipelineStageFlags2,
    dst_stage_mask: vk.PipelineStageFlags2,
    dependency_flags: vk.DependencyFlags = .{},

    memory_barriers: []const vk.MemoryBarrier2 = &.{},
    buffer_barriers: []const vk.BufferMemoryBarrier2 = &.{},
    image_barriers: []const vk.ImageMemoryBarrier2 = &.{},

    const Legacy = struct {
        src_stage_mask: vk.PipelineStageFlags,
        dst_stage_mask: vk.PipelineStageFlags,
        dependency_flags: vk.DependencyFlags,
        memory_barriers: ?[]const vk.MemoryBarrier,
        buffer_barriers: ?[]const vk.BufferMemoryBarrier,
        image_barriers: ?[]const vk.ImageMemoryBarrier,
    };

    fn truncateStageFlags(flags: vk.PipelineStageFlags2) ?vk.PipelineStageFlags {
        const legacy_mask: u64 = @intCast(~@as(u32, 0));

        if (flags.toInt() & ~legacy_mask != 0)
            return null;

        return @bitCast(@as(u32, @truncate(flags.toInt())));
    }

    fn truncateAccessFlags(flags: vk.AccessFlags2) ?vk.AccessFlags {
        const legacy_mask: u64 = @intCast(~@as(u32, 0));

        if (flags.toInt() & ~legacy_mask != 0)
            return null;

        return @bitCast(@as(u32, @truncate(flags.toInt())));
    }

    pub fn dependencyInfo(self: PipelineBarrierInfo) vk.DependencyInfo {
        return .{
            .dependency_flags = self.dependency_flags,
            .memory_barrier_count = @intCast(self.memory_barriers.len),
            .p_memory_barriers = if (self.memory_barriers.len > 0) self.memory_barriers.ptr else null,

            .buffer_memory_barrier_count = @intCast(self.buffer_barriers.len),
            .p_buffer_memory_barriers = if (self.buffer_barriers.len > 0) self.buffer_barriers.ptr else null,

            .image_memory_barrier_count = @intCast(self.image_barriers.len),
            .p_image_memory_barriers = if (self.image_barriers.len > 0) self.image_barriers.ptr else null,
        };
    }

    pub fn legacy(self: PipelineBarrierInfo, allocator: std.mem.Allocator) !Legacy {
        const src_stage = truncateStageFlags(self.src_stage_mask) orelse
            return error.UnsupportedStageMask;

        const dst_stage = truncateStageFlags(self.dst_stage_mask) orelse
            return error.UnsupportedStageMask;

        const memory_barriers_opt = if (self.memory_barriers.len > 0) try allocator.alloc(vk.MemoryBarrier, self.memory_barriers.len) else null;
        const buffer_barriers_opt = if (self.buffer_barriers.len > 0) try allocator.alloc(vk.BufferMemoryBarrier, self.buffer_barriers.len) else null;
        const image_barriers_opt = if (self.image_barriers.len > 0) try allocator.alloc(vk.ImageMemoryBarrier, self.image_barriers.len) else null;

        if (memory_barriers_opt) |memory_barriers| {
            for (self.memory_barriers, memory_barriers) |src, *dst| {
                dst.* = .{
                    .src_access_mask = truncateAccessFlags(src.src_access_mask) orelse
                        return error.UnsupportedAccessMask,
                    .dst_access_mask = truncateAccessFlags(src.dst_access_mask) orelse
                        return error.UnsupportedAccessMask,
                };
            }
        }

        if (buffer_barriers_opt) |buffer_barriers| {
            for (self.buffer_barriers, buffer_barriers) |src, *dst| {
                dst.* = .{
                    .src_access_mask = truncateAccessFlags(src.src_access_mask) orelse
                        return error.UnsupportedAccessMask,
                    .dst_access_mask = truncateAccessFlags(src.dst_access_mask) orelse
                        return error.UnsupportedAccessMask,
                    .src_queue_family_index = src.src_queue_family_index,
                    .dst_queue_family_index = src.dst_queue_family_index,
                    .buffer = src.buffer,
                    .size = src.size,
                    .offset = src.offset,
                };
            }
        }

        if (image_barriers_opt) |image_barriers| {
            for (self.image_barriers, image_barriers) |src, *dst| {
                dst.* = .{
                    .src_access_mask = truncateAccessFlags(src.src_access_mask) orelse
                        return error.UnsupportedAccessMask,
                    .dst_access_mask = truncateAccessFlags(src.dst_access_mask) orelse
                        return error.UnsupportedAccessMask,

                    .old_layout = src.old_layout,
                    .new_layout = src.new_layout,

                    .src_queue_family_index = src.src_queue_family_index,
                    .dst_queue_family_index = src.dst_queue_family_index,

                    .image = src.image,
                    .subresource_range = src.subresource_range,
                };
            }
        }

        return .{
            .src_stage_mask = src_stage,
            .dst_stage_mask = dst_stage,
            .dependency_flags = self.dependency_flags,
            .memory_barriers = memory_barriers_opt,
            .buffer_barriers = buffer_barriers_opt,
            .image_barriers = image_barriers_opt,
        };
    }
};

pub const PipelineBarrierError = StateError;

pub fn pipelineBarrier(
    self: *const CommandBuffer,
    src_stage_mask: vk.PipelineStageFlags,
    dst_stage_mask: vk.PipelineStageFlags,
    dependency_flags: vk.DependencyFlags,
    memory_barriers: ?[]const vk.MemoryBarrier,
    buffer_memory_barriers: ?[]const vk.BufferMemoryBarrier,
    image_memory_barriers: ?[]const vk.ImageMemoryBarrier,
) PipelineBarrierError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.in_render_pass)
        return error.InRenderPass;

    self.device.vkd.cmdPipelineBarrier(
        self.handle,
        src_stage_mask,
        dst_stage_mask,
        dependency_flags,
        if (memory_barriers) |b| @intCast(b.len) else 0,
        if (memory_barriers) |b| b.ptr else null,
        if (buffer_memory_barriers) |b| @intCast(b.len) else 0,
        if (buffer_memory_barriers) |b| b.ptr else null,
        if (image_memory_barriers) |b| @intCast(b.len) else 0,
        if (image_memory_barriers) |b| b.ptr else null,
    );
}

pub const PipelineBarrier2Error = StateError;

pub fn pipelineBarrier2(
    self: *const CommandBuffer,
    dependency_info: *const vk.DependencyInfo,
) PipelineBarrierError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.in_render_pass)
        return error.InRenderPass;

    self.device.vkd.cmdPipelineBarrier2(self.handle, dependency_info);
}

pub fn pipelineBarrierAuto(self: *const CommandBuffer, arina: std.mem.Allocator, info: PipelineBarrierInfo) !void {
    if (@as(u32, @bitCast(self.device.instance.version)) >=
        @as(u32, @bitCast(vk.API_VERSION_1_3)))
    {
        const dependency_info = info.dependencyInfo();
        try self.pipelineBarrier2(&dependency_info);
    } else {
        const legacy_info = try info.legacy(arina);

        try self.pipelineBarrier(
            legacy_info.src_stage_mask,
            legacy_info.dst_stage_mask,
            legacy_info.dependency_flags,
            legacy_info.memory_barriers,
            legacy_info.buffer_barriers,
            legacy_info.image_barriers,
        );
    }
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

    self.device.vkd.cmdExecuteCommands(self.handle, @intCast(cmds.len), cmds.ptr);
}

pub fn executeCommand(self: *const CommandBuffer, cmd: vk.CommandBuffer) ExecuteCommandsError!void {
    if (!self.recording)
        return error.NotRecording;

    if (self.level == .secondary)
        return error.OperationNotAllowedOnSecondary;

    self.device.vkd.cmdExecuteCommands(self.handle, 1, @ptrCast(&cmd));
}

pub const DrawError = StateError;

pub fn draw(
    self: *const CommandBuffer,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) DrawError!void {
    if (!self.recording)
        return error.NotRecording;

    self.device.vkd.cmdDraw(
        self.handle,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub const SetViewPortError = StateError;

pub fn setViewPort(
    self: *const CommandBuffer,
    view_port: *const vk.Viewport,
) SetViewPortError!void {
    if (!self.recording)
        return error.NotRecording;

    self.device.vkd.cmdSetViewport(self.handle, 0, 1, @as([*]const vk.Viewport, @ptrCast(view_port)));
}

pub const SetScissorError = StateError;

pub fn setScissor(
    self: *const CommandBuffer,
    scissor: *const vk.Rect2D,
) SetScissorError!void {
    if (!self.recording)
        return error.NotRecording;

    self.device.vkd.cmdSetScissor(self.handle, 0, 1, @as([*]const vk.Rect2D, @ptrCast(scissor)));
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("root.zig");
const Device = @import("Device.zig");
const CommandPool = @import("CommandPool.zig");
const RenderPass = @import("RenderPass.zig");
const Framebuffer = @import("Framebuffer.zig");
const Buffer = @import("Buffer.zig");

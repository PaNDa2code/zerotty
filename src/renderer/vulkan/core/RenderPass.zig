const std = @import("std");
const vk = @import("vulkan");
const Device = @import("Device.zig");

const RenderPass = @This();

device: *const Device,
handle: vk.RenderPass,

attachments: []const vk.AttachmentDescription,
subpasses: []const vk.SubpassDescription,
dependencies: []const vk.SubpassDependency,

pub const InitError = vk.DeviceWrapper.CreateRenderPassError;

pub fn init(
    device: *const Device,
    attachments: []const vk.AttachmentDescription,
    subpasses: []const vk.SubpassDescription,
    dependencies: []const vk.SubpassDependency,
) InitError!RenderPass {
    const create_info = vk.RenderPassCreateInfo{
        .flags = .{},
        .attachment_count = @intCast(attachments.len),
        .p_attachments = attachments.ptr,
        .subpass_count = @intCast(subpasses.len),
        .p_subpasses = subpasses.ptr,
        .dependency_count = @intCast(dependencies.len),
        .p_dependencies = dependencies.ptr,
    };

    const handle = try device.vkd.createRenderPass(
        device.handle,
        &create_info,
        device.vk_allocator,
    );

    return .{
        .device = device,
        .handle = handle,

        .attachments = attachments,
        .subpasses = subpasses,
        .dependencies = dependencies,
    };
}

pub fn deinit(self: *const RenderPass, allocator: std.mem.Allocator) void {
    allocator.free(self.attachments);
    allocator.free(self.subpasses);
    allocator.free(self.dependencies);

    self.device.vkd.destroyRenderPass(
        self.device.handle,
        self.handle,
        self.device.vk_allocator,
    );
}

pub const Builder = struct {
    arina: std.heap.ArenaAllocator,

    attachments: std.ArrayList(vk.AttachmentDescription),
    subpasses: std.ArrayList(vk.SubpassDescription),
    dependencies: std.ArrayList(vk.SubpassDependency),

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .arina = .init(allocator),
            .attachments = .empty,
            .subpasses = .empty,
            .dependencies = .empty,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.arina.deinit();
    }

    pub fn addAttachment(self: *Builder, attachment: vk.AttachmentDescription) !void {
        try self.attachments.append(self.arina.allocator(), attachment);
    }

    pub const Subpass = struct {
        pipeline_bind_point: vk.PipelineBindPoint = .graphics,
        input_attachments: []const vk.AttachmentReference = &.{},
        color_attachments: []const vk.AttachmentReference = &.{},
        resolve_attachments: []const vk.AttachmentReference = &.{},
        depth_stencil_attachment: ?vk.AttachmentReference = null,
        preserve_attachments: []const u32 = &.{},
    };

    pub fn addSubpass(self: *Builder, subpass: Subpass) !void {
        const allocator = self.arina.allocator();

        const input_refs = try allocator.dupe(vk.AttachmentReference, subpass.input_attachments);
        const color_refs = try allocator.dupe(vk.AttachmentReference, subpass.color_attachments);

        const resolve_refs = if (subpass.resolve_attachments.len > 0)
            try allocator.dupe(vk.AttachmentReference, subpass.resolve_attachments)
        else
            null;
        const preserve_refs = try allocator.dupe(u32, subpass.preserve_attachments);

        const depth_ref = if (subpass.depth_stencil_attachment) |d| blk: {
            const ptr = try allocator.create(vk.AttachmentReference);
            ptr.* = d;
            break :blk ptr;
        } else null;

        const description = vk.SubpassDescription{
            .flags = .{},
            .pipeline_bind_point = subpass.pipeline_bind_point,
            .input_attachment_count = @intCast(input_refs.len),
            .p_input_attachments = input_refs.ptr,
            .color_attachment_count = @intCast(color_refs.len),
            .p_color_attachments = color_refs.ptr,
            .p_resolve_attachments = if (resolve_refs) |r| r.ptr else null,
            .p_depth_stencil_attachment = depth_ref,
            .preserve_attachment_count = @intCast(preserve_refs.len),
            .p_preserve_attachments = preserve_refs.ptr,
        };

        try self.subpasses.append(allocator, description);
    }

    pub fn addDependency(self: *Builder, dependency: vk.SubpassDependency) !void {
        try self.dependencies.append(self.arina.allocator(), dependency);
    }

    pub const BuildError = std.mem.Allocator.Error || InitError;
    pub fn build(
        self: *Builder,
        device: *const Device,
    ) BuildError!RenderPass {
        const allocator = self.arina.child_allocator;

        return RenderPass.init(
            device,
            try allocator.dupe(vk.AttachmentDescription, self.attachments.items),
            try allocator.dupe(vk.SubpassDescription, self.subpasses.items),
            try allocator.dupe(vk.SubpassDependency, self.dependencies.items),
        );
    }
};

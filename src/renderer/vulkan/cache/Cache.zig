const Cache = @This();

textures: std.ArrayList(Texture),

max_textures_len: u32,
textures_width: u32,
textures_height: u32,

pub fn init(
    textures_width: u32,
    textures_height: u32,
    max_textures_len: u32,
) Cache {
    std.debug.assert(textures_width <= font.max_atlas_dim and
        textures_height <= font.max_atlas_dim and
        max_textures_len <= font.max_atlases_count);

    return .{
        .textures = .empty,
        .textures_width = @min(font.max_atlas_dim, textures_width),
        .textures_height = @min(font.max_atlas_dim, textures_height),
        .max_textures_len = @min(font.max_atlases_count, max_textures_len),
    };
}

pub fn newTexture(
    self: *Cache,
    allocator: std.mem.Allocator,
    device_allocator: *memory.DeviceAllocator,
) !*Texture {
    const texture = try Texture.init(device_allocator, .{
        .width = self.textures_width,
        .height = self.textures_height,
    });
    try self.textures.append(allocator, texture);
    return &self.textures.items[self.textures.items.len - 1];
}

pub fn updateDescriptorSet(
    self: *const Cache,
    descriptor_set: *core.DescriptorSet,
) !void {
    try descriptor_set.reset();

    for (self.textures.items, 0..) |*texture, i| {
        try descriptor_set.addDescriptor(0, @intCast(i), .{
            .image = texture.descriptorInfo(),
        });
    }
    descriptor_set.update();
}

pub fn recordCopyCmd(
    self: *Cache,
    cmd: *const core.CommandBuffer,
    buffer: *const core.Buffer,
    allocator: std.mem.Allocator,
    entries: []const font.GlyphAtlasEntry,
) !void {
    if (entries.len == 0) return;

    var arina = std.heap.ArenaAllocator.init(allocator);
    defer arina.deinit();
    const arina_alloc = arina.allocator();

    const texture_count = self.textures.items.len;

    var copy_lists = try arina_alloc.alloc(std.ArrayList(vk.BufferImageCopy), texture_count);

    for (copy_lists) |*list| {
        list.* = std.ArrayList(vk.BufferImageCopy).empty;
    }

    var buffer_offset: usize = 0;

    for (entries) |entry| {
        const texture_index: usize = @intCast(entry.atlas_id);

        const region_extent = vk.Extent3D{
            .width = @intCast(entry.width),
            .height = @intCast(entry.height),
            .depth = 1,
        };

        const region = vk.BufferImageCopy{
            .buffer_offset = buffer_offset,
            .buffer_row_length = @intCast(entry.width),
            .buffer_image_height = @intCast(entry.height),
            .image_offset = .{
                .x = @intCast(entry.x),
                .y = @intCast(entry.y),
                .z = 0,
            },
            .image_extent = region_extent,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        try copy_lists[texture_index].append(arina_alloc, region);

        buffer_offset += entry.width * entry.height;
    }

    for (copy_lists, 0..) |copy_list, texture_index| {
        if (copy_list.items.len == 0) continue;

        var tex = &self.textures.items[texture_index];

        try transitionImageLayout(
            cmd,
            tex.image.handle,
            .{ .color_bit = true },
            tex.layout,
            .transfer_dst_optimal,
            arina_alloc,
        );

        try cmd.copyBufferToImage(
            buffer.handle,
            tex.image.handle,
            .transfer_dst_optimal,
            copy_list.items,
        );

        try transitionImageLayout(
            cmd,
            tex.image.handle,
            .{ .color_bit = true },
            .transfer_dst_optimal,
            .shader_read_only_optimal,
            arina_alloc,
        );

        tex.layout = .shader_read_only_optimal;
    }
}

pub fn deinit(
    self: *Cache,
    allocator: std.mem.Allocator,
    device_allocator: *memory.DeviceAllocator,
) void {
    for (self.textures.items) |*texture| {
        texture.deinit(device_allocator);
    }
    self.textures.deinit(allocator);
}

fn transitionImageLayout(
    cmd_buffer: *const core.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    arina: std.mem.Allocator,
) !void {
    var src_access_mask: vk.AccessFlags2 = .{};
    var dst_access_mask: vk.AccessFlags2 = .{};
    var src_stage_mask: vk.PipelineStageFlags2 = .{};
    var dst_stage_mask: vk.PipelineStageFlags2 = .{};

    switch (old_layout) {
        .undefined, .preinitialized => {
            src_access_mask = .{};
            src_stage_mask.top_of_pipe_bit = true;
        },
        .transfer_dst_optimal => {
            src_access_mask.transfer_write_bit = true;
            src_stage_mask.all_transfer_bit = true;
        },
        .shader_read_only_optimal => {
            src_access_mask.shader_read_bit = true;
            src_stage_mask.all_graphics_bit = true;
        },
        else => {},
    }

    switch (new_layout) {
        .transfer_dst_optimal => {
            dst_access_mask.transfer_write_bit = true;
            dst_stage_mask.all_transfer_bit = true;
        },
        .shader_read_only_optimal => {
            dst_access_mask.shader_read_bit = true;
            dst_stage_mask.fragment_shader_bit = true;
        },
        else => {},
    }

    const barriers = [_]vk.ImageMemoryBarrier2{.{
        .src_access_mask = src_access_mask,
        .dst_access_mask = dst_access_mask,
        .src_stage_mask = src_stage_mask,
        .dst_stage_mask = dst_stage_mask,
        .old_layout = old_layout,
        .new_layout = new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresource_range = .{
            .aspect_mask = aspects,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }};

    try cmd_buffer.pipelineBarrierAuto(
        arina,
        .{
            .src_stage_mask = src_stage_mask,
            .dst_stage_mask = dst_stage_mask,
            .image_barriers = &barriers,
        },
    );
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");
const memory = core.memory;
const font = @import("font");
const Texture = @import("Texture.zig");

test Cache {
    const vk_testing = @import("../testing.zig");

    const device = vk_testing.getTestDeviceLocked();
    defer vk_testing.unlockTestDevice();

    var device_allocator = core.memory.DeviceAllocator.init(
        device,
        std.testing.allocator,
    );

    var cache = Cache.init(2046, 2046, 255);
    defer cache.deinit(std.testing.allocator, &device_allocator);

    _ = try cache.newTexture(
        std.testing.allocator,
        &device_allocator,
    );
}

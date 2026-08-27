const testing_target = @This();

const std = @import("std");
const vk = @import("vulkan");
const core = @import("../../core/root.zig");
const zigimg = @import("zigimg");

device: *const core.Device,
device_allocator: core.memory.DeviceAllocator,
queue: core.Queue,

image: core.Image,
framebuffer: core.Framebuffer,
render_pass: core.RenderPass,

command_pool: core.CommandPool,
command_buffer: core.CommandBuffer,

extent: vk.Extent2D,

pub fn init(allocator: std.mem.Allocator, extent: vk.Extent2D) !testing_target {
    const device = @import("../../testing.zig").getTestDevice();

    var device_allocator = core.memory.DeviceAllocator.init(device, allocator);

    const queue = core.Queue.init(
        device,
        0,
        device.physical_device.graphic_family_index,
        false,
    );

    var image_builder = core.Image.Builder.new();
    const image = try image_builder
        .setSize(extent.width, extent.height)
        .setFormat(.b8g8r8a8_srgb)
        .setUsage(.{
            .color_attachment_bit = true,
            .sampled_bit = true,
            .transfer_src_bit = true,
        })
        .build(&device_allocator);

    const render_pass = try createRenderPass(device, allocator);

    const framebuffer = try core.Framebuffer.init(
        device,
        &render_pass,
        &.{image.view},
        extent,
    );

    var command_pool = try core.CommandPool.init(device, device.physical_device.graphic_family_index);
    errdefer command_pool.deinit();

    const command_buffer = try command_pool.allocBuffer(.primary);

    return .{
        .device = device,
        .device_allocator = device_allocator,
        .queue = queue,
        .image = image,
        .framebuffer = framebuffer,
        .render_pass = render_pass,
        .command_pool = command_pool,
        .command_buffer = command_buffer,
        .extent = extent,
    };
}

pub fn deinit(self: *testing_target, allocator: std.mem.Allocator) void {
    self.command_pool.deinit();
    self.framebuffer.deinit(self.device);
    self.render_pass.deinit(allocator);
    self.image.deinit(&self.device_allocator);
}

pub fn renderClearColor(self: *testing_target, clear_color: [4]f32) !void {
    try self.command_buffer.begin(.{ .one_time_submit_bit = true });

    const clear_values = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = clear_color } },
    };

    try self.command_buffer.beginRenderPass(
        &self.render_pass,
        self.framebuffer,
        &clear_values,
        .@"inline",
    );

    try self.command_buffer.endRenderPass();
    try self.command_buffer.end();

    const fence = try self.device.createFence(false);
    defer self.device.destroyFence(fence);

    try self.queue.submitOne(
        &self.command_buffer,
        .null_handle,
        .null_handle,
        .{ .color_attachment_output_bit = true },
        fence,
    );

    _ = try self.device.waitFence(fence, std.math.maxInt(u64));
}

pub fn readBackPixels(self: *testing_target, allocator: std.mem.Allocator) ![]u8 {
    const pixel_count = self.extent.width * self.extent.height * 4;

    var staging = try core.Buffer.initAlloc(
        &self.device_allocator,
        pixel_count,
        .{ .transfer_dst_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );
    defer staging.deinit(&self.device_allocator);

    try self.command_buffer.begin(.{ .one_time_submit_bit = true });

    {
        const barrier = vk.ImageMemoryBarrier2{
            .src_stage_mask = .{ .all_commands_bit = true },
            .src_access_mask = .{ .memory_write_bit = true },
            .dst_stage_mask = .{ .all_commands_bit = true },
            .dst_access_mask = .{ .memory_read_bit = true },
            .old_layout = .shader_read_only_optimal,
            .new_layout = .transfer_src_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.image.handle,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        try self.command_buffer.pipelineBarrierAuto(allocator, .{
            .src_stage_mask = .{ .all_commands_bit = true },
            .dst_stage_mask = .{ .all_commands_bit = true },
            .image_barriers = &.{barrier},
        });
    }

    {
        const region = vk.BufferImageCopy{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,
            .image_subresource = .{
                .aspect_mask = .{ .color_bit = true },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = 1,
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{
                .width = self.extent.width,
                .height = self.extent.height,
                .depth = 1,
            },
        };

        self.device.vkd.cmdCopyImageToBuffer(
            self.command_buffer.handle,
            self.image.handle,
            .transfer_src_optimal,
            staging.handle,
            &.{region},
        );
    }

    {
        const barrier = vk.ImageMemoryBarrier2{
            .src_stage_mask = .{ .all_commands_bit = true },
            .src_access_mask = .{ .memory_write_bit = true },
            .dst_stage_mask = .{ .all_commands_bit = true },
            .dst_access_mask = .{ .memory_read_bit = true },
            .old_layout = .transfer_src_optimal,
            .new_layout = .shader_read_only_optimal,
            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.image.handle,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        try self.command_buffer.pipelineBarrierAuto(allocator, .{
            .src_stage_mask = .{ .all_commands_bit = true },
            .dst_stage_mask = .{ .all_commands_bit = true },
            .image_barriers = &.{barrier},
        });
    }

    try self.command_buffer.end();

    const fence = try self.device.createFence(false);
    defer self.device.destroyFence(fence);

    try self.queue.submitOne(
        &self.command_buffer,
        .null_handle,
        .null_handle,
        .{ .all_commands_bit = true },
        fence,
    );

    _ = try self.device.waitFence(fence, std.math.maxInt(u64));

    const slice = staging.hostSlice(u8) orelse
        return error.MemoryMapFailed;

    const pixels = try allocator.alloc(u8, pixel_count);
    @memcpy(pixels, slice[0..pixel_count]);

    return pixels;
}

pub fn savePng(self: *testing_target, io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const pixels = try self.readBackPixels(allocator);
    defer allocator.free(pixels);

    const rgba = try allocator.alloc(u8, self.extent.width * self.extent.height * 4);
    defer allocator.free(rgba);

    for (0..self.extent.width * self.extent.height) |i| {
        const src = i * 4;
        const b = pixels[src + 0];
        const g = pixels[src + 1];
        const r = pixels[src + 2];
        const a = pixels[src + 3];
        rgba[src + 0] = r;
        rgba[src + 1] = g;
        rgba[src + 2] = b;
        rgba[src + 3] = a;
    }

    const image = try zigimg.Image.fromRawPixelsOwned(
        self.extent.width,
        self.extent.height,
        rgba,
        .rgba32,
    );

    var write_buf: [1024 * 16]u8 = undefined;

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    try image.writeToFile(allocator, io, file, &write_buf, .{ .png = .{} });
}

pub fn savePpm(self: *testing_target, allocator: std.mem.Allocator, path: []const u8) !void {
    const pixels = try self.readBackPixels(allocator);
    defer allocator.free(pixels);

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const w = file.writer();
    try w.print("P6\n{d} {d}\n255\n", .{ self.extent.width, self.extent.height });

    for (0..self.extent.height) |y| {
        for (0..self.extent.width) |x| {
            const i = (y * self.extent.width + x) * 4;
            const b = pixels[i + 0];
            const g = pixels[i + 1];
            const r = pixels[i + 2];
            try w.writeAll(&.{ r, g, b });
        }
    }
}

fn createRenderPass(device: *const core.Device, allocator: std.mem.Allocator) !core.RenderPass {
    var builder = core.RenderPass.Builder.init(allocator);
    defer builder.deinit();

    try builder.addAttachment(.{
        .format = .b8g8r8a8_srgb,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .shader_read_only_optimal,
    });

    try builder.addSubpass(.{
        .pipeline_bind_point = .graphics,
        .color_attachments = &.{
            .{ .attachment = 0, .layout = .color_attachment_optimal },
        },
    });

    try builder.addDependency(.{
        .src_subpass = vk.SUBPASS_EXTERNAL,
        .dst_subpass = 0,
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = .{ .color_attachment_output_bit = true },
        .dst_access_mask = .{ .color_attachment_write_bit = true },
    });

    return builder.build(device);
}

test "clear color: red" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = try init(allocator, .{ .width = 64, .height = 64 });
    defer ctx.deinit(allocator);

    try ctx.renderClearColor(.{ 1.0, 0.0, 0.0, 1.0 });

    const pixels = try ctx.readBackPixels(allocator);
    defer allocator.free(pixels);

    try testing.expectEqual(@as(usize, 64 * 64 * 4), pixels.len);

    for (0..64 * 64) |i| {
        const b = pixels[i * 4 + 0];
        const g = pixels[i * 4 + 1];
        const r = pixels[i * 4 + 2];
        const a = pixels[i * 4 + 3];

        try testing.expectEqual(@as(u8, 255), r);
        try testing.expectEqual(@as(u8, 0), g);
        try testing.expectEqual(@as(u8, 0), b);
        try testing.expectEqual(@as(u8, 255), a);
    }
}

test "clear color: green" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = try init(allocator, .{ .width = 32, .height = 32 });
    defer ctx.deinit(allocator);

    try ctx.renderClearColor(.{ 0.0, 1.0, 0.0, 1.0 });

    const pixels = try ctx.readBackPixels(allocator);
    defer allocator.free(pixels);

    for (0..32 * 32) |i| {
        const b = pixels[i * 4 + 0];
        const g = pixels[i * 4 + 1];
        const r = pixels[i * 4 + 2];
        const a = pixels[i * 4 + 3];

        try testing.expectEqual(@as(u8, 0), r);
        try testing.expectEqual(@as(u8, 255), g);
        try testing.expectEqual(@as(u8, 0), b);
        try testing.expectEqual(@as(u8, 255), a);
    }
}

test "clear color: black" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var ctx = try init(allocator, .{ .width = 16, .height = 16 });
    defer ctx.deinit(allocator);

    try ctx.renderClearColor(.{ 0.0, 0.0, 0.0, 1.0 });

    const pixels = try ctx.readBackPixels(allocator);
    defer allocator.free(pixels);

    try ctx.savePng(allocator, "tests/samples/black.png");

    for (0..16 * 16) |i| {
        const b = pixels[i * 4 + 0];
        const g = pixels[i * 4 + 1];
        const r = pixels[i * 4 + 2];
        const a = pixels[i * 4 + 3];

        try testing.expectEqual(@as(u8, 0), r);
        try testing.expectEqual(@as(u8, 0), g);
        try testing.expectEqual(@as(u8, 0), b);
        try testing.expectEqual(@as(u8, 255), a);
    }
}

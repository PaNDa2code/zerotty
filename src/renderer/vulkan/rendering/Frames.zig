const Frames = @This();

pub const FrameResources = struct {
    command_pool: core.CommandPool,
    main_cmd: core.CommandBuffer,

    in_flight_fence: vk.Fence,

    vertex_buffer: core.Buffer,
    uniform_buffer: core.Buffer,

    descriptor_pool: core.DescriptorPool,
    descriptor_set: core.DescriptorSet,

    image_index: u32,

    // pub fn bindTexture(
    //     self: *FrameResources,
    //     allocator: std.mem.Allocator,
    //     texture: *Texture,
    //     binding: u32,
    //     index: u32,
    // ) !void {
    //     const descriptor_info = texture.image.getDescriptorImageInfo(texture.sampler);
    //     const entry = try self.descriptor_set.image_infos.getOrPutValue(binding, .empty);
    //
    //     try entry.value_ptr.insert(allocator, index, descriptor_info);
    // }
};

descriptor_layout: core.DescriptorSetLayout,

resources: []FrameResources,
current_frame: usize = 0,

images_in_flight: []vk.Fence,

image_available: []vk.Semaphore,
render_finished: []vk.Semaphore,

pub fn init(
    device: *const core.Device,
    allocator: std.mem.Allocator,
    max_frames_in_flight: usize,
    images_count: usize,
) !Frames {
    const resources = try allocator.alloc(FrameResources, max_frames_in_flight);

    const image_available = try allocator.alloc(vk.Semaphore, max_frames_in_flight);
    for (0..max_frames_in_flight) |i| {
        image_available[i] = try device.createSemaphore();
    }

    const render_finished = try allocator.alloc(vk.Semaphore, images_count);
    for (0..images_count) |i| {
        render_finished[i] = try device.createSemaphore();
    }

    const images_in_flight = try allocator.alloc(vk.Fence, images_count);
    @memset(images_in_flight, .null_handle);

    const descriptor_set_layout = try core.DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .addBinding(2, .storage_buffer, 1, .{ .vertex_bit = true })
        .addBinding(3, .storage_buffer, 1, .{ .vertex_bit = true })
        .build(device);

    errdefer descriptor_set_layout.deinit(device);

    for (0..max_frames_in_flight) |i| {
        resources[i].command_pool = try core.CommandPool.init(device, 0);
        resources[i].main_cmd = try resources[i].command_pool.allocBuffer(.primary);
        resources[i].in_flight_fence = try device.createFence(true);

        resources[i].vertex_buffer = try core.Buffer.init(
            device,
            1024 * 1024 * 16,
            .{ .vertex_buffer_bit = true },
            .exclusive,
        );

        resources[i].uniform_buffer = try core.Buffer.init(
            device,
            @sizeOf(root.vertex.Uniforms),
            .{ .uniform_buffer_bit = true },
            .exclusive,
        );

        resources[i].descriptor_pool = try core.DescriptorPool.Builder
            .addPoolSize(.uniform_buffer, 1)
            .addPoolSize(.storage_buffer, 2)
            .addPoolSize(.combined_image_sampler, 1)
            .build(device);

        const buffer_infos_map = try allocator.create(std.AutoHashMap(u32, std.ArrayList(vk.DescriptorBufferInfo)));
        const image_infos_map = try allocator.create(std.AutoHashMap(u32, std.ArrayList(vk.DescriptorImageInfo)));

        buffer_infos_map.* = .init(allocator);
        image_infos_map.* = .init(allocator);

        resources[i].descriptor_set =
            try core.DescriptorSet.init(
                &resources[i].descriptor_pool,
                &descriptor_set_layout,
                allocator,
                buffer_infos_map,
                image_infos_map,
            );
    }

    return .{
        .resources = resources,
        .descriptor_layout = descriptor_set_layout,
        .images_in_flight = images_in_flight,

        .image_available = image_available,
        .render_finished = render_finished,
    };
}

pub fn deinit(self: *Frames, device: *const core.Device, allocator: std.mem.Allocator) void {
    for (self.image_available) |sem| {
        device.destroySemaphore(sem);
    }

    for (self.render_finished) |sem| {
        device.destroySemaphore(sem);
    }

    self.descriptor_layout.deinit(device);

    for (self.resources) |frame| {
        device.destroyFence(frame.in_flight_fence);

        frame.descriptor_pool.deinit();
        frame.command_pool.deinit();
        frame.vertex_buffer.deinit(null);
        frame.uniform_buffer.deinit(null);

        allocator.destroy(frame.descriptor_set.buffer_infos);
        allocator.destroy(frame.descriptor_set.image_infos);
    }

    allocator.free(self.images_in_flight);
    allocator.free(self.render_finished);
    allocator.free(self.image_available);
    allocator.free(self.resources);
}

pub fn frameBegin(
    self: *Frames,
    device: *const core.Device,
    swapchain: *const core.Swapchain,
) !*FrameResources {
    const frame = &self.resources[self.current_frame];

    const image_available = self.image_available[self.current_frame];

    _ = try device.waitFence(frame.in_flight_fence, std.math.maxInt(u64));
    _ = try device.resetFence(frame.in_flight_fence);

    const acquire_result = try swapchain.acquireNextImage(
        std.math.maxInt(u64),
        image_available,
        .null_handle,
    );

    const image_index =
        switch (acquire_result) {
            .success, .suboptimal_khr => |index| index,
            else => unreachable,
        };

    const image_fence = self.images_in_flight[image_index];
    if (image_fence != .null_handle and
        image_fence != frame.in_flight_fence)
    {
        _ = try device.waitFence(image_fence, std.math.maxInt(u64));
    }
    self.images_in_flight[image_index] = frame.in_flight_fence;

    try frame.command_pool.reset(false);

    frame.image_index = image_index;
    return frame;
}

pub fn endFrame(self: *Frames) !void {
    _ = self;
}

pub fn submit(
    self: *Frames,
    graphics_queue: *const core.Queue,
    present_queue: ?*const core.Queue,
    swapchain: *const core.Swapchain,
) !void {
    const frame = &self.resources[self.current_frame];

    const image_index = frame.image_index;
    const image_available = self.image_available[self.current_frame];
    const render_finished = self.render_finished[frame.image_index];
    const in_flight_fence = frame.in_flight_fence;

    try graphics_queue.submitOne(
        &frame.main_cmd,
        image_available,
        render_finished,
        .{ .color_attachment_output_bit = true },
        in_flight_fence,
    );

    var queue = present_queue orelse graphics_queue;

    _ = try queue.presentOne(
        swapchain,
        render_finished,
        image_index,
    );

    self.current_frame = (self.current_frame + 1) % self.resources.len;
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");

const root = @import("../../root.zig");

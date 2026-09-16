const FrameManager = @This();

pub const FrameResources = struct {
    command_pool: core.CommandPool,
    main_cmd: core.CommandBuffer,

    in_flight_fence: vk.Fence,

    vertex_buffer: core.Buffer,
    uniform_buffer: core.Buffer,

    descriptor_pool: core.DescriptorPool,
    descriptor_sets: []core.DescriptorSet,

    pending_copy_count: usize = 0,
};

uniform_stage: core.Buffer,

descriptor_layouts: []core.DescriptorSetLayout,
device_allocator: *core.memory.DeviceAllocator,

resources: []FrameResources,
current_frame: usize = 0,

device: *const core.Device,

pub fn init(
    device: *const core.Device,
    device_allocator: *core.memory.DeviceAllocator,
    allocator: std.mem.Allocator,
    max_frames_in_flight: usize,
) !FrameManager {
    const resources = try allocator.alloc(FrameResources, max_frames_in_flight);

    const descriptor_set_layouts = try allocator.alloc(core.DescriptorSetLayout, 2);
    errdefer allocator.free(descriptor_set_layouts);

    descriptor_set_layouts[0] = try core.DescriptorSetLayout.Builder
        .addBinding(0, .uniform_buffer, 1, .{ .vertex_bit = true, .fragment_bit = true })
        .addBinding(1, .combined_image_sampler, 1, .{ .fragment_bit = true })
        .build(device);
    errdefer descriptor_set_layouts[0].deinit(device);

    descriptor_set_layouts[1] = try core.DescriptorSetLayout.Builder
        .addBinding(0, .combined_image_sampler, 255, .{ .fragment_bit = true })
        .build(device);
    errdefer descriptor_set_layouts[1].deinit(device);

    for (0..max_frames_in_flight) |i| {
        resources[i].command_pool = try core.CommandPool.init(device, 0);
        resources[i].main_cmd = try resources[i].command_pool.allocBuffer(.primary);
        resources[i].in_flight_fence = try device.createFence(true);

        resources[i].vertex_buffer = try core.Buffer.initAlloc(
            device_allocator,
            1024 * 1024 * 16,
            .{ .vertex_buffer_bit = true, .transfer_dst_bit = true },
            .{ .device_local_bit = true },
            .exclusive,
        );

        resources[i].uniform_buffer = try core.Buffer.initAlloc(
            device_allocator,
            @sizeOf(root.vertex.Uniforms),
            .{ .uniform_buffer_bit = true, .transfer_dst_bit = true },
            .{ .host_visible_bit = true, .host_coherent_bit = true },
            .exclusive,
        );

        resources[i].descriptor_pool = try core.DescriptorPool.Builder
            .addPoolSize(.uniform_buffer, 1)
            .addPoolSize(.combined_image_sampler, 256)
            .setMaxSets(2)
            .build(device);

        resources[i].descriptor_sets = try allocator.alloc(
            core.DescriptorSet,
            descriptor_set_layouts.len,
        );
        errdefer allocator.free(resources[i].descriptor_sets);

        for (descriptor_set_layouts, 0..) |*layout, j| {
            resources[i].descriptor_sets[j] =
                try core.DescriptorSet.init(&resources[i].descriptor_pool, layout, allocator);
        }
    }

    const staging = try core.Buffer.initAlloc(
        device_allocator,
        @sizeOf(vertex.TextUniform),
        .{ .transfer_src_bit = true },
        .{ .host_visible_bit = true, .host_coherent_bit = true },
        .exclusive,
    );

    return .{
        .resources = resources,
        .descriptor_layouts = descriptor_set_layouts,
        .device_allocator = device_allocator,
        .device = device,
        .uniform_stage = staging,
    };
}

pub fn deinit(self: *FrameManager, allocator: std.mem.Allocator) void {
    const device = self.device;

    for (self.descriptor_layouts) |layout| {
        layout.deinit(device);
    }

    for (self.resources) |*frame| {
        device.destroyFence(frame.in_flight_fence);

        frame.descriptor_pool.deinit();
        frame.command_pool.deinit();
        frame.vertex_buffer.deinit(self.device_allocator);
        frame.uniform_buffer.deinit(self.device_allocator);

        for (frame.descriptor_sets) |*ds| {
            ds.deinit();
        }
        allocator.free(frame.descriptor_sets);
    }

    allocator.free(self.resources);
    allocator.free(self.descriptor_layouts);

    self.uniform_stage.deinit(self.device_allocator);
}

pub fn beginFrame(self: *FrameManager) !*FrameResources {
    const frame = &self.resources[self.current_frame];

    _ = try self.device.waitFence(frame.in_flight_fence, std.math.maxInt(u64));
    _ = try self.device.resetFence(frame.in_flight_fence);

    try frame.command_pool.reset(false);

    return frame;
}

pub fn advanceFrame(self: *FrameManager) void {
    self.current_frame = (self.current_frame + 1) % self.resources.len;
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("../core/root.zig");

const root = @import("../../root.zig");
const vertex = @import("../../vertex.zig");

const Texture = @This();

const vk = @import("vulkan");

const Atlas = @import("../../font/Atlas.zig");

const Core = @import("Core.zig");
const Command = @import("Command.zig");
const SwapChian = @import("SwapChain.zig");

const Buffers = @import("Buffers.zig");
const findMemoryType = Buffers.findMemoryType;

image: vk.Image,
image_view: vk.ImageView,
image_memory: vk.DeviceMemory,
sampler: vk.Sampler,

pub const TextureCreateOptions = struct {
    height: u32,
    width: u32,
};

pub fn init(
    core: *const Core,
    options: TextureCreateOptions,
) !Texture {
    const vkd = &core.dispatch.vkd;
    const vki = &core.dispatch.vki;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();

    const mem_properties =
        vki.getPhysicalDeviceMemoryProperties(core.physical_device);

    const image_info = vk.ImageCreateInfo{
        .image_type = .@"2d",
        .format = .r8_unorm,
        .extent = .{
            .width = @intCast(options.width),
            .height = @intCast(options.height),
            .depth = 1,
        },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{
            .transfer_dst_bit = true,
            .sampled_bit = true,
        },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };

    const image =
        try vkd.createImage(
            core.device,
            &image_info,
            &alloc_callbacks,
        );

    const mem_requrements =
        vkd.getImageMemoryRequirements(core.device, image);

    const alloc_info =
        vk.MemoryAllocateInfo{
            .allocation_size = mem_requrements.size,
            .memory_type_index = findMemoryType(
                &mem_properties,
                mem_requrements.memory_type_bits,
                .{ .device_local_bit = true },
            ),
        };

    const image_memory =
        try vkd.allocateMemory(
            core.device,
            &alloc_info,
            &alloc_callbacks,
        );

    try vkd.bindImageMemory(core.device, image, image_memory, 0);

    const image_view_info = vk.ImageViewCreateInfo{
        .image = image,
        .view_type = .@"2d",
        .format = .r8_unorm,
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
        .components = .{ .r = .r, .g = .identity, .b = .identity, .a = .identity },
    };

    const image_view =
        try vkd.createImageView(
            core.device,
            &image_view_info,
            &alloc_callbacks,
        );

    const sampler_info = vk.SamplerCreateInfo{
        .mag_filter = .linear,
        .min_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
        .address_mode_w = .repeat,
        .anisotropy_enable = .false,
        .max_anisotropy = 1.0,
        .border_color = .int_opaque_black,
        .unnormalized_coordinates = .false,
        .compare_enable = .false,
        .compare_op = .always,
        .mipmap_mode = .linear,
        .max_lod = 0.0,
        .min_lod = 0.0,
        .mip_lod_bias = 0.0,
    };

    const sampler = try vkd.createSampler(
        core.device,
        &sampler_info,
        &alloc_callbacks,
    );

    return .{
        .image = image,
        .image_view = image_view,
        .image_memory = image_memory,
        .sampler = sampler,
    };
}

pub fn deinit(
    self: *const Texture,
    core: *const Core,
) void {
    const vkd = &core.dispatch.vkd;
    const alloc_callbacks = core.vk_mem.vkAllocatorCallbacks();
    vkd.destroyImageView(core.device, self.image_view, &alloc_callbacks);
    vkd.destroyImage(core.device, self.image, &alloc_callbacks);
    vkd.freeMemory(core.device, self.image_memory, &alloc_callbacks);
    vkd.destroySampler(core.device, self.sampler, &alloc_callbacks);
}

pub fn uploadAtlas(
    self: *const Texture,
    core: *const Core,
    buffers: *const Buffers,
    cmd: *const Command,
    atlas: *const Atlas,
) !void {
    const vkd = &core.dispatch.vkd;
    const cmd_buffer = cmd.buffers[1];

    const bytes = atlas.buffer.len;
    const statging_ptr: [*]u8 =
        @ptrCast(try vkd.mapMemory(
            core.device,
            buffers.staging_buffer.memory,
            0,
            bytes,
            .{},
        ));

    @memcpy(statging_ptr[0..bytes], atlas.buffer);

    vkd.unmapMemory(core.device, buffers.staging_buffer.memory);

    const begin_info = vk.CommandBufferBeginInfo{};

    try vkd.beginCommandBuffer(cmd_buffer, &begin_info);

    transitionImageLayout(
        vkd,
        cmd_buffer,
        self.image,
        .{ .color_bit = true },
        .undefined,
        .transfer_dst_optimal,
    );

    const copy_region = vk.BufferImageCopy{
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
            .width = @intCast(atlas.width),
            .height = @intCast(atlas.height),
            .depth = 1,
        },
    };

    vkd.cmdCopyBufferToImage(
        cmd_buffer,
        buffers.staging_buffer.handle,
        self.image,
        .transfer_dst_optimal,
        1,
        &.{copy_region},
    );

    transitionImageLayout(
        vkd,
        cmd_buffer,
        self.image,
        .{ .color_bit = true },
        .transfer_dst_optimal,
        .shader_read_only_optimal,
    );

    try vkd.endCommandBuffer(cmd_buffer);

    const submit_info = vk.SubmitInfo{
        .s_type = .submit_info,
        .wait_semaphore_count = 0,
        .p_wait_semaphores = null,
        .p_wait_dst_stage_mask = null,
        .command_buffer_count = 1,
        .p_command_buffers = &[_]vk.CommandBuffer{cmd_buffer},
        .signal_semaphore_count = 0,
        .p_signal_semaphores = null,
    };

    try vkd.queueSubmit(core.graphics_queue, 1, &.{submit_info}, .null_handle);
    try vkd.queueWaitIdle(core.graphics_queue);
}

fn transitionImageLayout(
    vkd: *const vk.DeviceWrapper,
    cmd_buffer: vk.CommandBuffer,
    image: vk.Image,
    aspects: vk.ImageAspectFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
) void {
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

    const barrier = vk.ImageMemoryBarrier2{
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
    };

    const dep = vk.DependencyInfo{
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &.{barrier},
    };

    vkd.cmdPipelineBarrier2(cmd_buffer, &dep);
}

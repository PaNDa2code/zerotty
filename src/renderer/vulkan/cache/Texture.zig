const Texture = @This();

image: core.Image,
sampler: core.Sampler,

pub const TextureOptions = struct {
    width: u32,
    height: u32,
    format: vk.Format = .r8_unorm,
    inital_data: ?[]const u8 = null,
};

pub const InitError = core.Sampler.InitError ||
    core.Image.Builder.BuildError;

pub fn init(
    device_allocator: *memory.DeviceAllocator,
    options: TextureOptions,
) InitError!Texture {
    // const width = try std.math.ceilPowerOfTwo(u32, options.width);
    // const height = try std.math.ceilPowerOfTwo(u32, options.height);

    const width = options.width;
    const height = options.height;

    if (options.inital_data) |data| {
        std.debug.assert(data.len == width * height);
    }

    var image_builder = core.Image.Builder.new();

    const image =
        try image_builder
            .setFormat(options.format)
            .setSize(width, height)
            .addUsage(.{ .sampled_bit = true, .transfer_dst_bit = true })
            .setMipLevels(1)
            .build(device_allocator);

    errdefer image.deinit(device_allocator);

    const sampler = try core.Sampler.init(device_allocator.device, .{});

    return .{
        .image = image,
        .sampler = sampler,
    };
}

pub fn deinit(self: *const Texture, device_allocator: *memory.DeviceAllocator) void {
    self.image.deinit(device_allocator);
    self.sampler.deinit(device_allocator.device);
}

const std = @import("std");
const vk = @import("vulkan");
const core = @import("core");
const memory = @import("memory");

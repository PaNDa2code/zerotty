pub const Atlas = struct {
    image: core.Image,

    row_extent: u32,
    row_baseline: u32,
    row_tallest: u32,
};

pub const CreateEmptyAtlasError = core.Image.Builder.BuildError;

pub fn createEmptyAtlas(
    device_allocator: *memory.DeviceAllocator,
    width: u32,
    height: u32,
) CreateEmptyAtlasError!Atlas {
    var image_builder = core.Image.Builder.new();

    const image = try image_builder
        .addUsage(.{ .transfer_dst_bit = true })
        .setSize(width, height)
        .setFormat(.r8_unorm)
        .asTexture()
        .build(device_allocator);

    return .{
        .image = image,
        .row_extent = 0,
        .row_baseline = 0,
        .row_tallest = 0,
    };
}

pub const RecoredAtlasUpdate = error{};

pub fn recoredAtlasUpdate(
    atlas: *Atlas,
    cmd: *const core.CommandBuffer,
    staging_buffer: *const core.Buffer,
    data: []const u8,
) RecoredAtlasUpdate!void {
    const staging = staging_buffer.hostSlice(u8) orelse return;
    @memcpy(staging, data);

    try cmd.copyBufferToImage(
        staging_buffer.handle,
        atlas.image.handle,
    );
}

const core = @import("../core/root.zig");
const memory = @import("../memory/root.zig");

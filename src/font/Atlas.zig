const Atlas = @This();

buffer: []u8,

height: usize,
width: usize,

cell_height: u16,
cell_width: u16,

rows: u32,
cols: u32,

from: u32,
to: u32,

pub const CreateError = freetype.Error || Allocator.Error || SaveAtlasError;

// TODO: glyphs are not placed corrctly on the baseline
pub fn create(
    allocator: Allocator,
    cell_height: u16,
    cell_width: u16,
    from: u32,
    to: u32,
) !Atlas {
    const glyph_count = to - from + 1;

    const cols: u32 = @intFromFloat(@ceil(@sqrt(@as(f32, @floatFromInt(glyph_count)))));
    const rows: u32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(glyph_count)) / @as(f32, @floatFromInt(cols))));

    const atlas_width = cols * cell_width;
    const atlas_height = rows * cell_height;

    const buffer_size = atlas_width * atlas_height;
    const buffer = try allocator.alloc(u8, buffer_size);
    errdefer allocator.free(buffer);

    @memset(buffer, 0);

    const ft_lib = try freetype.Library.init(allocator);
    defer ft_lib.deinit();

    var face = try ft_lib.memoryFace(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf", cell_width);
    defer face.deinit();

    try face.setPixelSize(@intCast(cell_height), @intCast(cell_width));

    const metrics = face.ft_face.*.size.*.metrics;
    const descender: i32 = @intCast(-metrics.descender >> 6);
    const baseline: usize = @as(usize, @intCast(cell_height)) - @min(@as(usize, @intCast(descender)), cell_height);

    var char = from;
    while (char <= to) : (char += 1) {
        var glyph = try face.getGlyph(@intCast(char));
        defer glyph.deinit();

        const bitmap_glyph = try glyph.glyphBitmap();
        if (bitmap_glyph.top <= 0 or bitmap_glyph.bitmap.buffer == null) continue;

        const bitmap = &bitmap_glyph.bitmap;
        const bitmap_w = bitmap.width;
        const bitmap_h = bitmap.rows;

        const index = char - from;
        const col = index % cols;
        const row = index / cols;

        const origin_x = col * cell_width;
        const origin_y = row * cell_height;

        const dst_x = origin_x + (cell_width - bitmap_w) / 2;

        const top = bitmap_glyph.top;
        const dst_y = origin_y + baseline - @min(@as(usize, @intCast(top)), baseline);
        const max_h = if (dst_y >= atlas_height) 0 else @min(bitmap_h, atlas_height - dst_y);

        const pitch: usize = @intCast(bitmap.pitch);
        for (0..max_h) |y| {
            const src_row = bitmap.buffer.?[y * pitch ..][0..pitch];
            const dst_row_start = (dst_y + y) * atlas_width + dst_x;
            const dst_row = buffer[dst_row_start..][0..pitch];
            @memcpy(dst_row, src_row);
        }
    }

    if (builtin.mode == .Debug)
        try saveAtlas(allocator, "temp/atlas.png", buffer, atlas_width, atlas_height);

    return .{
        .buffer = buffer,
        .cell_height = cell_height,
        .cell_width = cell_width,
        .height = atlas_height,
        .width = atlas_width,
        .rows = rows,
        .cols = cols,
        .from = from,
        .to = to,
    };
}

pub fn deinit(self: *Atlas, allocator: Allocator) void {
    allocator.free(self.buffer);
    self.* = std.mem.zeroes(Atlas);
}

const SaveAtlasError = std.fs.File.OpenError || std.io.AnyWriter.Error;

pub fn saveAtlas(
    allocator: Allocator,
    filename: []const u8,
    data: []const u8,
    width: usize,
    height: usize,
) !void {
    const image = try zigimg.ImageUnmanaged.fromRawPixelsOwned(width, height, data, .grayscale8);
    try image.writeToFilePath(allocator, filename, .{ .png = .{} });
}

const std = @import("std");
const builtin = @import("builtin");
const freetype = @import("freetype");
const assets = @import("assets");
const zigimg = @import("zigimg");
const Allocator = std.mem.Allocator;

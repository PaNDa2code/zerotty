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

// Create one raw glyph atlas
pub fn create(allocator: Allocator, cell_height: u16, cell_width: u16, from: u32, to: u32) CreateError!Atlas {
    const glyph_count = to - from;
    const glyph_size = cell_height * cell_width; // m^2

    const atlas_width = cell_width * glyph_count;
    const atlas_height = cell_height;

    const buffer_size = glyph_size * glyph_count + 100;
    const buffer = try allocator.alloc(u8, buffer_size);
    errdefer allocator.free(buffer);

    @memset(buffer, 0);

    const ft_lib = try freetype.Library.init(allocator);
    defer ft_lib.deinit();

    var face = try ft_lib.face("assets/fonts/FiraCodeNerdFontMono-Regular.ttf", cell_width);
    defer face.deinit();

    try face.setPixelSize(@intCast(cell_height),@intCast(cell_width));

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


        const dst_x = index * cell_width + (cell_width - bitmap_w) / 2;
        const dst_y = cell_height - @min(@as(usize, @intCast(bitmap_glyph.top)), cell_height);

        const max_w = @min(bitmap_w, cell_width - (dst_x - index * cell_width));
        const max_h = if (dst_y >= atlas_height) 0 else @min(bitmap_h, atlas_height - dst_y);

        for (0..max_h) |y| {
            for (0..max_w) |x| {
                const src_idx = y * @as(usize, @intCast(bitmap.pitch)) + x;
                const dst_idx = (dst_y + y) * atlas_width + (dst_x + x);
                buffer[dst_idx] = bitmap.buffer.?[src_idx];
            }
        }
    }

    try saveAtlasAsPGM("atlas.PGM", buffer, atlas_width, atlas_height);

    return .{
        .buffer = buffer,
        .cell_height = cell_height,
        .cell_width = cell_width,
        .height = atlas_height,
        .width = atlas_width,
        .rows = 1,
        .cols = glyph_count,
        .from = from,
        .to = to,
    };
}

pub fn deinit(self: *Atlas, allocator: Allocator) void {
    allocator.free(self.buffer);
    self.* = std.mem.zeroes(Atlas);
}

const SaveAtlasError = std.fs.File.OpenError || std.io.AnyWriter.Error;

fn saveAtlasAsPGM(
    filename: []const u8,
    data: []const u8,
    width: usize,
    height: usize,
) SaveAtlasError!void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const writer = file.writer();

    // Write PGM header
    try writer.print("P5\n{} {}\n255\n", .{ width, height });

    // Write raw grayscale pixel data
    try writer.writeAll(data);
}

const std = @import("std");
const freetype = @import("freetype");
const Allocator = std.mem.Allocator;

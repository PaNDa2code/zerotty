const Atlas = @This();

pub const GlyphInfo = packed struct {
    coord_start: Vec2(u32),
    coord_end: Vec2(u32),
    bearing: Vec2(u32),
};

buffer: []u8,
glyph_lookup_map: std.AutoHashMap(u32, GlyphInfo),

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
pub fn create(allocator: Allocator, cell_height: u16, cell_width: u16, from: u32, to: u32) !Atlas {
    const glyphs_count = to - from;
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    const ft_face = try ft_library.memoryFace(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf", 0);
    defer ft_face.deinit();

    // font should always be monospace (at least for now)
    std.debug.assert(ft_face.isFixedWidth());

    // try ft_face.setCharSize(0, @as(u32, @intCast(cell_height)) << 6, 96, 96);
    try ft_face.setPixelSize(cell_width, cell_height);

    const atlas_cols = std.math.sqrt(glyphs_count);
    const atlas_rows = try std.math.divCeil(u32, glyphs_count, atlas_cols);

    // const padding_x = 1;
    const padding_y = 1;

    const glyph_height = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.height - ft_face.ft_face.*.size.*.metrics.descender)) >> 6);
    const glyph_width = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.max_advance)) >> 6);

    // const tex_width = (glyph_width + padding_x) * atlas_cols;
    const tex_height = (glyph_height + padding_y) * atlas_rows;
    const tex_width = tex_height;

    var pixels = try allocator.alloc(u8, tex_width * tex_height);
    @memset(pixels, 0);
    var glyph_map = std.AutoHashMap(u32, GlyphInfo).init(allocator);

    var pin: Vec2(u32) = .zero;
    for (from..to) |c| {
        var glyph = try ft_face.getGlyph(@intCast(c));
        defer glyph.deinit();

        const bitmap_glyph = try glyph.glyphBitmap();
        const bitmap = bitmap_glyph.bitmap;

        if (pin.x + bitmap.width > tex_width) {
            pin.x = 0;
            pin.y += glyph_height;
        }

        for (0..bitmap.rows) |row| {
            const src_start = row * @as(usize, @intCast(bitmap.pitch));
            const src_row = bitmap.buffer.?[src_start .. src_start + bitmap.width];

            const dst_start = (pin.y + row) * tex_width + pin.x;
            const dst_row = pixels[dst_start .. dst_start + bitmap.width];

            @memcpy(dst_row, src_row);
        }

        const glyph_info: GlyphInfo = .{
            .coord_start = pin,
            .coord_end = .{ .x = pin.x + bitmap.width, .y = pin.y + bitmap.rows },
            .bearing = .{
                .x = @intCast(glyph.ft_glyph.advance.x >> 6),
                .y = @intCast(glyph.ft_glyph.advance.y >> 6),
            },
        };
        try glyph_map.put(@intCast(c), glyph_info);

        // Advance to next position
        pin.x += glyph_width;
    }

    if (builtin.mode == .Debug)
        try saveAtlas(allocator, "temp/atlas.png", pixels, tex_width, tex_height);

    return .{
        .buffer = pixels,
        .height = tex_height,
        .width = tex_width,
        .glyph_lookup_map = glyph_map,
        .cell_width = @intCast(glyph_width),
        .cell_height = @intCast(glyph_height),
        .rows = atlas_rows,
        .cols = atlas_cols,
        .from = from,
        .to = to,
    };
}

// pub fn lookupGlyph(self: *Atlas, char_code: u32) void {}

pub fn deinit(self: *Atlas, allocator: Allocator) void {
    allocator.free(self.buffer);
    self.glyph_lookup_map.deinit();
}

const SaveAtlasError = std.fs.File.OpenError || std.io.AnyWriter.Error;

pub fn saveAtlas(
    allocator: Allocator,
    filename: []const u8,
    data: []const u8,
    width: usize,
    height: usize,
) !void {
    if (std.fs.path.dirname(filename)) |dir_path| {
        _ = try std.fs.cwd().makePath(dir_path);
    }
    const image = try zigimg.ImageUnmanaged.fromRawPixelsOwned(width, height, data, .grayscale8);
    try image.writeToFilePath(allocator, filename, .{ .png = .{} });
}

const std = @import("std");
const builtin = @import("builtin");
const freetype = @import("freetype");
const assets = @import("assets");
const zigimg = @import("zigimg");
const Allocator = std.mem.Allocator;

const math = @import("../renderer/math.zig");
const Vec2 = math.Vec2;

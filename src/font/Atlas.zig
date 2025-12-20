const Atlas = @This();

pub const GlyphInfo = extern struct {
    coord_start: Vec2(u32),
    coord_end: Vec2(u32),
    bearing: Vec2(i32),
};

buffer: []u8,
glyph_lookup_map: std.AutoArrayHashMap(u32, GlyphInfo),

height: usize,
width: usize,

cell_height: u16,
cell_width: u16,

descender: i32,

rows: u32,
cols: u32,

from: u32,
to: u32,

pub const CreateError = freetype.Error || Allocator.Error || SaveAtlasError;

// TODO: glyphs are not placed correctly on the baseline
pub fn create(allocator: Allocator, cell_height: u16, cell_width: u16, from: u32, to: u32) CreateError!Atlas {
    const glyphs_count = to - from;
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    const ft_face = try ft_library.memoryFace(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf", 0);
    defer ft_face.deinit();

    // font should always be monospace (at least for now)
    std.debug.assert(ft_face.isFixedWidth());

    try ft_face.setPixelSize(cell_width, cell_height);

    const atlas_cols = std.math.sqrt(glyphs_count);
    const atlas_rows = try std.math.divCeil(u32, glyphs_count, atlas_cols);

    const padding_x = 0;
    const padding_y = 0;

    const max_glyph_height = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.height)) >> 6);
    const glyph_width = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.max_advance)) >> 6);
    const descender = (@as(i32, @intCast(ft_face.ft_face.*.size.*.metrics.descender)) >> 6);

    const tex_height = (max_glyph_height + padding_y) * atlas_rows;
    const tex_width = tex_height;

    var pixels = try allocator.alloc(u8, tex_width * tex_height);
    if (builtin.mode == .Debug)
        @memset(pixels, 0);

    var glyph_map = std.AutoArrayHashMap(u32, GlyphInfo).init(allocator);

    var line_height: u32 = 0;
    var pin: Vec2(u32) = .zero;

    for (from..to) |c| {
        var glyph = try ft_face.getGlyph(@intCast(c));
        defer glyph.deinit();

        const bitmap_glyph = try glyph.glyphBitmap();
        const bitmap = bitmap_glyph.bitmap;

        line_height = @max(line_height, bitmap.rows);

        if (pin.x + bitmap.width > tex_width) {
            pin.x = 0;
            pin.y += line_height;
            line_height = 0;
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
            .bearing = .{ .x = bitmap_glyph.left, .y = bitmap_glyph.top },
        };

        try glyph_map.put(@intCast(c), glyph_info);

        // Advance to next position
        pin.x += bitmap.width + padding_x;
    }

    if (builtin.mode == .Debug)
        try saveAtlas(allocator, "temp/atlas.png", pixels, tex_width, tex_height);

    return .{
        .buffer = pixels,
        .height = tex_height,
        .width = tex_width,
        .glyph_lookup_map = glyph_map,
        .cell_width = @intCast(glyph_width),
        .cell_height = @intCast(cell_height - descender),
        .descender = descender,
        .rows = atlas_rows,
        .cols = atlas_cols,
        .from = from,
        .to = to,
    };
}

pub fn loadAll(allocator: Allocator, cell_height: u16, cell_width: u16, max_glyphs: usize) CreateError!Atlas {
    const ft_library = try freetype.Library.init(allocator);
    defer ft_library.deinit();

    const ft_face = try ft_library.memoryFace(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf", 0);
    defer ft_face.deinit();

    // font should always be monospace (at least for now)
    std.debug.assert(ft_face.isFixedWidth());

    try ft_face.setPixelSize(cell_width, cell_height);

    const glyphs_count = @min(@as(usize, @intCast(ft_face.ft_face.*.num_glyphs)), max_glyphs);
    const atlas_cols = std.math.sqrt(glyphs_count);
    const atlas_rows = try std.math.divCeil(usize, glyphs_count, atlas_cols);

    const padding_x = 0;
    const padding_y = 0;

    const max_glyph_height = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.height)) >> 6);
    const glyph_width = (@as(u32, @intCast(ft_face.ft_face.*.size.*.metrics.max_advance)) >> 6);
    const descender = (@as(i32, @intCast(ft_face.ft_face.*.size.*.metrics.descender)) >> 6);

    const tex_height = (max_glyph_height + padding_y) * atlas_rows;
    const tex_width = tex_height;

    var glyph_map = std.AutoArrayHashMap(u32, GlyphInfo).init(allocator);
    var pixels = try allocator.alloc(u8, tex_width * tex_height);
    if (builtin.mode == .Debug)
        @memset(pixels, 0);

    _ = freetype.c.FT_Select_Charmap(@ptrCast(ft_face.ft_face), freetype.c.FT_ENCODING_UNICODE);

    var line_height: u32 = 0;
    var pin: Vec2(u32) = .zero;

    var char_code: c_ulong = 0;
    var gid: c_uint = 0;
    char_code = freetype.c.FT_Get_First_Char(@ptrCast(ft_face.ft_face), &gid);

    var counter: usize = 0;

    while (gid != 0) : (char_code = freetype.c.FT_Get_Next_Char(@ptrCast(ft_face.ft_face), char_code, &gid)) {
        defer counter += 1;
        if (counter == glyphs_count) break;
        
        var glyph = try ft_face.getGlyph(@intCast(char_code));
        defer glyph.deinit();

        const bitmap_glyph = try glyph.glyphBitmap();
        const bitmap = bitmap_glyph.bitmap;

        line_height = @max(line_height, bitmap.rows);

        if (pin.x + bitmap.width > tex_width) {
            pin.x = 0;
            pin.y += line_height;
            line_height = 0;
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
            .bearing = .{ .x = bitmap_glyph.left, .y = bitmap_glyph.top },
        };

        try glyph_map.put(@intCast(char_code), glyph_info);

        // Advance to next position
        pin.x += bitmap.width + padding_x;
    }

    if (builtin.mode == .Debug)
        try saveAtlas(allocator, "temp/atlas.png", pixels, tex_width, tex_height);

    return .{
        .buffer = pixels,
        .height = tex_height,
        .width = tex_width,
        .glyph_lookup_map = glyph_map,
        .cell_width = @intCast(glyph_width),
        .cell_height = @intCast(cell_height - descender),
        .descender = descender,
        .rows = @intCast(atlas_rows),
        .cols = @intCast(atlas_cols),
        .from = 0,
        .to = 0,
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
    var buff: [1024 * 16]u8 = undefined;
    if (std.fs.path.dirname(filename)) |dir_path| {
        _ = try std.fs.cwd().makePath(dir_path);
    }
    const image = try zigimg.Image.fromRawPixelsOwned(width, height, data, .grayscale8);
    try image.writeToFilePath(allocator, filename, &buff, .{ .png = .{} });
}

const std = @import("std");
const builtin = @import("builtin");
const freetype = @import("freetype");
const assets = @import("assets");
const zigimg = @import("zigimg");
const Allocator = std.mem.Allocator;

const math = @import("../renderer/common/math.zig");
const Vec2 = math.Vec2;

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

pub const CreateError = TrueType.GlyphBitmapError || Allocator.Error || SaveAtlasError;

// TODO: glyphs are not placed correctly on the baseline
pub fn create(allocator: Allocator, cell_height: u16, cell_width: u16, from: u32, to: u32) CreateError!Atlas {
    const glyphs_count = to - from;
    const ttf = try TrueType.load(assets.fonts.@"FiraCodeNerdFontMono-Regular.ttf");
    const scale = ttf.scaleForPixelHeight(@floatFromInt(cell_height));

    var buffer = try std.ArrayList(u8).initCapacity(allocator, cell_height * cell_width);
    defer buffer.deinit(allocator);

    const atlas_cols = std.math.sqrt(glyphs_count);
    const atlas_rows = try std.math.divCeil(u32, glyphs_count, atlas_cols);

    const padding_x = 2;
    const padding_y = 2;

    const tex_height = try std.math.ceilPowerOfTwo(u32, (cell_height + padding_y) * atlas_rows);
    const tex_width = tex_height;

    var pixels = try allocator.alloc(u8, tex_width * tex_height);

    if (builtin.mode == .Debug)
        @memset(pixels, 0);

    var glyph_map = std.AutoArrayHashMap(u32, GlyphInfo).init(allocator);

    var line_height: u32 = 0;
    var pin: Vec2(u32) = .zero;

    for (from..to) |codepoint| {
        const glyph_index = ttf.codepointGlyphIndex(@intCast(codepoint));
        if (glyph_index == .notdef) continue;
        buffer.clearRetainingCapacity();
        const dims = ttf.glyphBitmap(allocator, &buffer, glyph_index, scale, scale) catch |err| {
            switch (err) {
                error.GlyphNotFound => continue,
                else => return err,
            }
        };
        const bitmap = buffer.items;

        if (pin.x + dims.width > tex_width) {
            pin.x = 0;
            pin.y += line_height + padding_y;
            line_height = 0;
        }

        for (0..dims.height) |row| {
            const src_start = dims.width * row;
            const src_row = bitmap[src_start..][0..dims.width];

            const dst_start = (pin.y + row) * tex_width + pin.x;
            const dst_row = pixels[dst_start..][0..dims.width];

            @memcpy(dst_row, src_row);
        }

        const glyph_info: GlyphInfo = .{
            .coord_start = pin,
            .coord_end = .{ .x = pin.x + dims.width, .y = pin.y + dims.height },
            .bearing = .{ .x = dims.off_x, .y = dims.off_y },
        };

        try glyph_map.put(@intCast(codepoint), glyph_info);

        // Advance to next position
        pin.x += dims.width + padding_x;

        line_height = @max(line_height, dims.height);
    }

    if (builtin.mode == .Debug)
        try saveAtlas(allocator, "temp/atlas.png", pixels, tex_width, tex_height);

    return .{
        .buffer = pixels,
        .height = tex_height,
        .width = tex_width,
        .glyph_lookup_map = glyph_map,
        .cell_width = cell_width,
        .cell_height = cell_height,
        .descender = 0,
        .rows = atlas_rows,
        .cols = atlas_cols,
        .from = from,
        .to = to,
    };
}

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
const assets = @import("assets");
const zigimg = @import("zigimg");
const Allocator = std.mem.Allocator;

const math = @import("math");
const Vec2 = math.Vec2;

const TrueType = @import("TrueType");

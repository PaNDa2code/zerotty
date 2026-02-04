const std = @import("std");
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;

pub const max_atlas_dim = maxInt(u12);
pub const max_glyph_dim = maxInt(u8);
pub const max_bearing = maxInt(i8);
pub const min_bearing = minInt(i8);

pub const GlyphAtlasEntry = packed struct(u64) {
    // postion
    atlas_id: u8,
    x: u12,
    y: u12,

    // Metrics
    width: u8,
    height: u8,
    x_bearing: i8,
    y_bearing: i8,
};

pub const FontID = enum(u32) { _ };
pub const GlyphIndex = enum(u32) { _ };

pub const GlyphID = packed struct(u64) {
    font: FontID,
    index: GlyphIndex,
};

pub const Cache = @import("Cache.zig");

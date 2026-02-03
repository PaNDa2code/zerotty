pub const Atlas = @import("Atlas.zig");

pub const GlyphAtlasEntry = packed struct(u64) {
    // postion
    atlas_id: u8, // max atlases count is 256
    x: u12,
    y: u12, // max 4096

    // Metrics
    width: u8,
    height: u8, // max 255
    x_bearing: i8,
    y_bearing: i8, // max 127, min -128
};

pub const FontID = enum(u32) { _ };
pub const GlyphIndex = enum(u32) { _ };

pub const GlyphID = packed struct(u64) {
    font: FontID,
    index: GlyphIndex,
};

test Atlas {
    const std = @import("std");
    const allocator = std.testing.allocator;

    var atlas = try Atlas.create(
        allocator,
        30,
        20,
        0x2500,
        0x257F,
    );
    defer atlas.deinit(allocator);
}

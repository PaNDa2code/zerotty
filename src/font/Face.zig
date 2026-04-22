const Face = @This();

pub const Style = packed struct {
    bold: bool = false,
    italic: bool = false,
};

font: *const Font,
style: Style,

pub fn deinit(self: *const Font) void {
    _ = self;
}

pub fn lookupCodepointGlyph(self: *const Face, codepoint: u21) !root.GlyphIndex {
    const glyph_index = self.font.ttf.codepointGlyphIndex(codepoint);

    if (glyph_index == .notdef)
        return error.GlyphNotFound;

    return @enumFromInt(
        @intFromEnum(glyph_index),
    );
}

pub fn glyphBitmap(
    self: *const Face,
    allocator: std.mem.Allocator,
    buffer: *std.ArrayList(u8),
    glyph_index: root.GlyphIndex,
) !void {
    try self.font.ttf.glyphBitmap(
        allocator,
        buffer,
        glyph_index,
        self.font.scale_x,
        self.font.scale_y,
    );
}

const std = @import("std");
const root = @import("font");
const Font = @import("Font.zig");

const std = @import("std");
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;

pub const max_atlas_dim = maxInt(u12);
pub const max_glyph_dim = maxInt(u8);
pub const max_bearing = maxInt(i8);
pub const min_bearing = minInt(i8);
pub const max_atlases_count = maxInt(u8);

/// Terminal cell geometry, derived from the primary face's own metrics by
/// `FontInterface.cellMetrics`.
pub const CellMetrics = struct {
    cell_width: u8,
    cell_height: u8,
    baseline: u8,
};

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

    pub fn toInt(entry: GlyphAtlasEntry) u64 {
        return @bitCast(entry);
    }
};

pub const FontID = enum(u32) { _ };
pub const GlyphIndex = enum(u32) { _ };

pub const GlyphID = packed struct(u64) {
    font: FontID,
    index: GlyphIndex,

    pub fn toInt(id: GlyphID) u64 {
        return @bitCast(id);
    }
};

pub const Cache = @import("Cache.zig");
// pub const Layout = @import("Layout.zig");
// pub const Atlas = @import("Atlas.zig");
pub const FontManager = @import("FontManager.zig");
pub const Style = @import("Style.zig");
pub const backend = @import("backend.zig");
pub const TrueTypeBackend = @import("truetype_backend.zig");
pub const FreeTypeBackend = @import("freetype_backend.zig");

// Aliased rather than exported under its own name: the import *is* the module's
// namespace type, which would shadow the `FontInterface` generic function and
// make `FontInterface(TrueTypeBackend)` a call on a type.
const font_interface = @import("FontInterface.zig");

/// The `FontInterface` generic itself, re-exported so out-of-tree callers can
/// instantiate a face over either backend. Exported under a distinct name
/// because the import alias `font_interface` is the module namespace type and
/// would otherwise shadow it.
pub const makeFontInterface = font_interface.FontInterface;

/// Selects the rasterizer. Both backends implement `backend.zig`'s contract and
/// are interchangeable; changing this line switches the whole app's font
/// engine, which is the point of the abstraction.
///
/// FreeType is not a strict superset of TrueType -- it additionally handles
/// CFF/PostScript outlines, WOFF containers, and hinting via autohinter -- but
/// for the plain TrueType faces in the asset archive the two produce the same
/// glyphs.
pub const default_backend = TrueTypeBackend;

/// The concrete interface zerotty runs on.
pub const Font = makeFontInterface(default_backend);

comptime {
    @import("std").testing.refAllDecls(@This());
}

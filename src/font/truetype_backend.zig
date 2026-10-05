//! TrueType backend: adapts the `TrueType` dependency to `backend.zig`.
//!
//! This is the reference implementation of the contract. The TrueType library
//! it wraps reports metrics in unscaled font units and takes a scale factor per
//! rasterization call, which matches the contract directly, so most of this
//! file is mechanical translation. The one non-mechanical part is
//! `setSize`: TrueType has no size-setting call at all, so the scale factor is
//! computed from the font's own vertical extent and cached.

const std = @import("std");
const TrueType = @import("TrueType");
const backend = @import("backend.zig");

const TrueTypeBackend = @This();

const Self = @This();

ttf: TrueType,
/// Font units -> pixels. Computed once in `setSize`.
scale_x: f32 = 0,
scale_y: f32 = 0,
/// True while `ttf` holds a parsed face.
loaded: bool = false,

/// Parses `bytes` as a TrueType font.
///
/// The buffer is borrowed, never copied: `TrueType` retains pointers into it.
/// The caller must keep it alive for as long as this backend is used.
pub fn init(bytes: []const u8) !Self {
    return .{
        .ttf = try TrueType.load(bytes),
        .loaded = true,
    };
}

pub fn deinit(self: *Self) void {
    // Nothing to release: TrueType holds borrowed views, and the byte buffer
    // belongs to whoever passed it to `init`.
    self.loaded = false;
}

pub fn isLoaded(self: *const Self) bool {
    return self.loaded;
}

/// Sets the rasterized size, in pixels, for the font's full line height.
///
/// Mirrors `Font.cellMetrics`: the requested pixel height is the span from
/// ascent to descent plus line gap, and the scale is derived from that. The
/// horizontal scale matches the vertical one so glyphs are not stretched.
pub fn setSize(self: *Self, pixel_height: f32) void {
    if (!self.loaded) {
        self.scale_x = 0;
        self.scale_y = 0;
        return;
    }

    const vm = self.ttf.verticalMetrics();
    const line_height: f32 = @floatFromInt(vm.ascent - vm.descent + vm.line_gap);
    if (line_height == 0) {
        self.scale_x = 0;
        self.scale_y = 0;
        return;
    }

    self.scale_y = pixel_height / line_height;
    self.scale_x = self.scale_y;
}

pub fn scale(self: *const Self) f32 {
    return self.scale_x;
}

/// Returns the glyph index for `codepoint`, or `0` (`.notdef`) when the font
/// has no glyph for it.
///
/// Note the conflation this inherits from the underlying library: index 0 means
/// both "codepoint absent from cmap" and "cmap entry points at glyph 0". That
/// is the contract's intended meaning, since either case means "ask a fallback
/// font".
pub fn glyphIndexForCodepoint(self: *const Self, codepoint: u21) u32 {
    return @intFromEnum(self.ttf.codepointGlyphIndex(codepoint));
}

pub fn glyphMetrics(self: *const Self, glyph: u32) backend.GlyphMetrics {
    const index: TrueType.GlyphIndex = @enumFromInt(@as(u16, @intCast(glyph)));
    return .{ .advance = self.ttf.glyphHMetrics(index).advance_width };
}

pub fn verticalMetrics(self: *const Self) backend.VerticalMetrics {
    const vm = self.ttf.verticalMetrics();
    return .{
        .ascent = vm.ascent,
        .descent = vm.descent,
        .line_gap = vm.line_gap,
    };
}

/// Rasterizes `glyph`, appending 8-bit coverage pixels to `pixels`.
///
/// Uses the backend's own error set, which callers must be able to name
/// generically; `FontInterface` translates it into its own.
pub fn glyphBitmap(
    self: *const Self,
    allocator: std.mem.Allocator,
    pixels: *std.ArrayList(u8),
    glyph: u32,
) !backend.Bitmap {
    if (!self.loaded or self.scale_x == 0)
        return backend.empty_bitmap;

    const index: TrueType.GlyphIndex = @enumFromInt(@as(u16, @intCast(glyph)));

    const bmp = try self.ttf.glyphBitmap(allocator, pixels, index, self.scale_x, self.scale_y);

    if (bmp.width == 0 or bmp.height == 0) return backend.empty_bitmap;

    return .{
        .width = @intCast(bmp.width),
        .height = @intCast(bmp.height),
        .off_x = bmp.off_x,
        .off_y = bmp.off_y,
    };
}

comptime {
    backend.assertBackend(TrueTypeBackend);
    std.testing.refAllDecls(@This());
}

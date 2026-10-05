//! FreeType backend: adapts `mach-freetype` to `backend.zig`.
//!
//! This is the second implementation of the contract, and it is where the
//! value of normalizing shows up. FreeType differs from TrueType on three
//! points that would otherwise leak upward:
//!
//! - **Scaling is set on the face, not passed per call.** `setSize` becomes a
//!   `setPixelSizes` call, and the scale factor TrueType wants has nowhere to
//!   go.
//! - **Metrics come back in 26.6 fixed-point pixels, not font units.** All
//!   metric reads use `FT_LOAD_NO_SCALE` so the values are converted back to
//!   font units here, keeping the contract's "unscaled font units" promise.
//! - **Glyph indices are `null`, not 0, for absent codepoints.**
//!
//! Bitmap pitch can be negative (bottom-up rows) and need not be a multiple of
//! the width, so rows are flipped and repacked rather than handed over as-is.

const std = @import("std");
const ft = @import("mach-freetype");
const backend = @import("backend.zig");

const FreeTypeBackend = @This();

const Self = @This();

/// One library per process: FreeType keeps global state, and creating several
/// is wasteful. Shared by every face.
///
/// Not thread-safe by design. FreeType's own library handle is not safe to
/// initialize concurrently, and a lock here would need an `Io` to block on,
/// which the backend contract has no room for. Font loading happens once on the
/// main thread during startup, so this is a documented precondition rather than
/// a hole. Faces are independent once created and *are* safe to use
/// concurrently, one face per thread.
var library: ?ft.Library = null;

/// Faces sharing the library above. The library outlives all of them: it is
/// torn down only when the last face is deinited.
var live_faces: usize = 0;

const Face = ft.Face;

ttf: Face,
loaded: bool = false,
/// Pixel height last passed to `setSize`.
pixel_height: f32 = 0,
/// Font units -> pixels, derived in `setSize` and cached so `scale` agrees with
/// what FreeType was actually told to do.
scale_px: f32 = 0,

pub fn init(bytes: []const u8) !Self {
    const lib = try acquireLibrary();
    errdefer releaseLibrary();

    return .{
        .ttf = try lib.createFaceMemory(bytes, 0),
        .loaded = true,
    };
}

pub fn deinit(self: *Self) void {
    if (!self.loaded) return;
    self.loaded = false;
    self.ttf.deinit();
    releaseLibrary();
}

pub fn isLoaded(self: *const Self) bool {
    return self.loaded;
}

fn acquireLibrary() !ft.Library {
    if (library == null) {
        library = try ft.Library.init();
    }
    live_faces += 1;
    return library.?;
}

fn releaseLibrary() void {
    if (live_faces == 0) return;
    live_faces -= 1;

    if (live_faces == 0) {
        if (library) |lib| lib.deinit();
        library = null;
    }
}

/// Sets the face's pixel size, rounding to the whole pixels FreeType requires.
///
/// Only the vertical size is set; the horizontal size is left unset so that
/// glyph advances keep their font's own proportions rather than being forced to
/// a fixed width.
pub fn setSize(self: *Self, pixel_height: f32) void {
    if (!self.loaded) {
        self.pixel_height = 0;
        self.scale_px = 0;
        return;
    }

    const vm = self.verticalMetrics();
    const line_height: f32 = @floatFromInt(vm.ascent - vm.descent + vm.line_gap);
    if (line_height <= 0) {
        self.pixel_height = 0;
        self.scale_px = 0;
        return;
    }

    // `setPixelSizes` would interpret the argument as the em square, i.e. it
    // scales font units by px/unitsPerEm. The contract instead defines the size
    // as the font's own line height, so the scale must be px/lineHeight -- for
    // JetBrains Mono that is 32/1320 rather than 32/1000, which made every
    // FreeType glyph about a third wider than the TrueType one.
    //
    // `setCharSize` is used rather than `setPixelSizes` because its argument is
    // 26.6 fixed point, so the intended scale survives without being rounded to
    // whole pixels.
    const units_per_em: f32 = @floatFromInt(self.ttf.unitsPerEM());
    const target_scale: f32 = pixel_height / line_height;
    const char_height: f32 = target_scale * units_per_em * 64.0;

    self.ttf.setCharSize(0, @intFromFloat(@max(64.0, @round(char_height))), 72, 72) catch {
        self.pixel_height = 0;
        self.scale_px = 0;
        return;
    };

    self.pixel_height = pixel_height;
    self.scale_px = target_scale;
}

pub fn scale(self: *const Self) f32 {
    return self.scale_px;
}

/// The unscaled-load flag used for every metric read.
///
/// Without it FreeType reports metrics in 26.6 pixels, which would make
/// `verticalMetrics` depend on the current size and break the contract's
/// promise that metrics are font units.
const unscaled: ft.LoadFlags = .{ .no_scale = true };

pub fn glyphIndexForCodepoint(self: *const Self, codepoint: u21) u32 {
    if (!self.loaded) return backend.notdef;
    return self.ttf.getCharIndex(codepoint) orelse backend.notdef;
}

pub fn glyphMetrics(self: *const Self, glyph: u32) backend.GlyphMetrics {
    if (!self.loaded) return .{ .advance = 0 };
    self.ttf.loadGlyph(glyph, unscaled) catch return .{ .advance = 0 };

    const m = self.ttf.glyph().metrics();
    // Under FT_LOAD_NO_SCALE the metrics are already in font units: 600 for
    // JetBrains Mono, matching what the TrueType backend reports. FreeType's
    // types alias horiAdvance to FT_Pos, which is nominally 26.6 fixed point,
    // but no scaling is applied here so the value must not be divided by 64.
    return .{ .advance = @intCast(m.horiAdvance) };
}

pub fn verticalMetrics(self: *const Self) backend.VerticalMetrics {
    if (!self.loaded) return .{ .ascent = 0, .descent = 0, .line_gap = 0 };

    // Already unscaled font units: these `FT_FaceRec` fields are FT_Short, not
    // the FT_Pos used elsewhere in the library. That is what `NO_SCALE` on
    // glyph reads has to match.
    const ascent: i32 = self.ttf.ascender();
    const descent: i32 = self.ttf.descender();
    const height: i32 = self.ttf.height();

    // FreeType has no line-gap accessor; the gap is whatever the font's total
    // line height leaves over after ascent and descent.
    const line_gap: i32 = height - (ascent - descent);

    return .{ .ascent = ascent, .descent = descent, .line_gap = line_gap };
}

/// Rasterizes `glyph`, appending 8-bit coverage pixels to `pixels`.
pub fn glyphBitmap(
    self: *const Self,
    allocator: std.mem.Allocator,
    pixels: *std.ArrayList(u8),
    glyph: u32,
) !backend.Bitmap {
    if (!self.loaded or self.pixel_height == 0) return backend.empty_bitmap;

    // Hinting is disabled so that rasterization matches the TrueType backend,
    // which scales outlines without hinting. Leaving FreeType's default hinting on
    // snapped stems to the pixel grid and produced a narrower bitmap (11px vs 15px
    // at the same nominal size) for identical glyphs.
    try self.ttf.loadGlyph(glyph, .{ .render = true, .no_hinting = true });

    const slot = self.ttf.glyph();
    const bmp = slot.bitmap();
    const w = bmp.width();
    const h = bmp.rows();
    if (w == 0 or h == 0) return backend.empty_bitmap;

    const src = bmp.buffer() orelse return backend.empty_bitmap;
    const pitch = bmp.pitch();

    const start = pixels.items.len;
    try pixels.resize(allocator, start + @as(usize, w) * h);

    const dst = pixels.items[start..];
    for (0..h) |row| {
        // A negative pitch means rows are stored bottom-up.
        const src_row: usize = if (pitch < 0)
            @intCast(@as(usize, @intCast(h - 1 - row)) * @as(usize, @intCast(-pitch)))
        else
            @intCast(@as(usize, @intCast(row)) * @as(usize, @intCast(pitch)));

        const from = src[src_row..][0..w];
        const to = dst[row * w ..][0..w];

        // LCD subpixel modes pack three bytes per pixel; only plain grayscale
        // and mono fit the 8-bit coverage contract directly.
        switch (bmp.pixelMode()) {
            .gray, .mono => @memcpy(to, from),
            else => @memset(to, 0),
        }
    }

    // bitmap_left/bitmap_top are in pixels, measured from the baseline origin.
    return .{
        .width = w,
        .height = h,
        .off_x = slot.bitmapLeft(),
        // freetype y offset is flipped
        .off_y = slot.bitmapTop() * -1,
    };
}

comptime {
    backend.assertBackend(FreeTypeBackend);
    std.testing.refAllDecls(@This());
}

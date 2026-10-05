//! The font backend contract.
//!
//! `Backend` is a *concept*, not a type: it is the set of declarations a
//! backend must provide, described once here and checked at compile time by
//! `assertBackend`. `FontInterface` is generic over any type satisfying it, so
//! adding a rasterizer means writing one new file and one build import — no
//! change to the interface, the cache, or the renderer.
//!
//! ## Why a concept and not a base class
//!
//! Font libraries expose genuinely different vocabularies. TrueType reports
//! metrics in unscaled font units and takes a scale factor per rasterization
//! call. FreeType reports metrics in 26.6 fixed-point pixels and takes a pixel
//! size set on the face. A subclass hierarchy would have to paper over that
//! with virtual calls and a lowest-common-denominator return type; a comptime
//! contract keeps each backend's own types and still gets the same error
//! messages.
//!
//! ## Normalization
//!
//! The contract normalizes two things the backends disagree about, because
//! everything above this layer depends on them being consistent:
//!
//! - **Glyph indices** are `u32` with `0` meaning `.notdef`. FreeType already
//!   reports `null` for index 0; TrueType returns a non-exhaustive enum.
//! - **Metrics are unscaled font units.** Both backends are asked for
//!   unscaled values (`FT_LOAD_NO_SCALE`) so that scaling happens in exactly
//!   one place -- `FontInterface` -- rather than once per backend.

const std = @import("std");

/// A glyph bitmap: 8 bits per pixel, 0 transparent, 255 opaque, stored
/// left-to-right and top-to-bottom with no row padding.
pub const Bitmap = struct {
    width: u32,
    height: u32,
    /// Offset in pixels from the glyph origin to the left of the bitmap.
    off_x: i32,
    /// Offset in pixels from the glyph origin to the top of the bitmap.
    off_y: i32,
};

pub const empty_bitmap: Bitmap = .{ .width = 0, .height = 0, .off_x = 0, .off_y = 0 };

/// Per-glyph horizontal metrics, in font units.
pub const GlyphMetrics = struct {
    /// Horizontal distance from the current position to the next one.
    advance: i32,
};

/// Vertical metrics, in font units.
pub const VerticalMetrics = struct {
    /// Distance above the baseline the font extends.
    ascent: i32,
    /// Distance below the baseline the font extends (negative for most fonts).
    descent: i32,
    /// Extra space between one row's descent and the next row's ascent.
    line_gap: i32,
};

/// Glyph index 0 is `.notdef`: the shape a font draws when it has nothing
/// better. A codepoint mapping to 0 is *not* present in the font, which is
/// what makes it usable as a fallback-chain signal.
pub const notdef: u32 = 0;

pub fn isNotdef(glyph: u32) bool {
    return glyph == notdef;
}

/// Compile-time assertion that `T` satisfies the backend contract.
///
/// Called from each backend and once from `FontInterface` instantiation, so a
/// backend that drifts out of contract fails at the point of drift rather than
/// deep inside the renderer.
pub fn assertBackend(comptime T: type) void {
    // The declared name may itself be a type, so ask what kind of thing it is
    // before assuming it is a namespace.
    if (@TypeOf(T) != type)
        @compileError("font backend must be a struct type, got " ++ @typeName(T));

    if (@typeInfo(T) != .@"struct")
        @compileError("font backend must be a struct, got " ++ @typeName(T));

    const required = .{
        .{ "init", "fn ([]const u8) @" ++ @typeName(T) ++ "!void" },
        .{ "deinit", "fn (*@" ++ @typeName(T) ++ ") void" },
        .{ "setSize", "fn (*@" ++ @typeName(T) ++ ", f32) void" },
        .{ "glyphIndexForCodepoint", "fn (*const @" ++ @typeName(T) ++ ", u21) u32" },
        .{ "glyphMetrics", "fn (*const @" ++ @typeName(T) ++ ", u32) " ++ @typeName(GlyphMetrics) },
        .{ "verticalMetrics", "fn (*const @" ++ @typeName(T) ++ ") " ++ @typeName(VerticalMetrics) },
        .{ "glyphBitmap", "fn (*const @" ++ @typeName(T) ++ ", std.mem.Allocator, *std.ArrayList(u8), u32) " ++ @typeName(Bitmap) ++ "!void" },
    };

    inline for (required) |req| {
        if (!@hasDecl(T, req[0]))
            @compileError("font backend " ++ @typeName(T) ++ " is missing `" ++ req[0] ++ "`");
    }
}

comptime {
    std.testing.refAllDecls(@This());
}

test "notdef is index zero" {
    try std.testing.expect(isNotdef(0));
    try std.testing.expect(!isNotdef(1));
}

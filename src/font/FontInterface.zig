//! Rasterization layer: a font backend plus the size it is drawn at.
//!
//! `FontInterface` is generic over any type satisfying the contract in
//! `backend.zig`, so the choice of rasterizer is a type argument rather than a
//! branch. `FontInterface(TrueTypeBackend)` and `FontInterface(FreeTypeBackend)`
//! are the same code with different backends; everything downstream -- the
//! glyph cache, the atlas packer, the renderer -- is backend-agnostic.
//!
//! This replaces a vtable (`?*anyopaque` plus a function table) that was tried
//! here first. It failed twice over: the only entry it declared was a factory
//! rather than an operation, so nothing could be called through it, and every
//! call site would have had to hand-cast `ctx` back to a concrete type anyway.
//! A comptime parameter gives the same substitutability, keeps concrete types,
//! turns contract violations into compile errors, and costs nothing at runtime.

const std = @import("std");
const backend = @import("backend.zig");
const root = @import("root.zig");

const Allocator = std.mem.Allocator;

/// A font, bound to a rasterization size.
///
/// Note the shape of this type: it holds the backend inline and exposes only
/// the normalized vocabulary from `backend.zig`. Backend-specific types do not
/// appear in its public API, which is what keeps callers portable across
/// rasterizers.
pub fn FontInterface(comptime B: type) type {
    backend.assertBackend(B);

    return struct {
        const Self = @This();

        pub const CellMetrics = root.CellMetrics;
        pub const Bitmap = backend.Bitmap;

        /// Font units -> pixels, derived from `setSize`.
        pub const scale_t = f32;

        b: B,
        scale_x: f32 = 0,
        scale_y: f32 = 0,

        /// Parses `bytes` with the given backend.
        ///
        /// The buffer is borrowed, never copied or freed: backends hold
        /// pointers into it for their whole lifetime. The caller must keep it
        /// alive. In practice that means the font registry holds every loaded
        /// buffer for as long as any face refers to it.
        pub fn init(bytes: []const u8) !Self {
            return .{ .b = try B.init(bytes) };
        }

        pub fn deinit(self: *Self) void {
            self.b.deinit();
            self.scale_x = 0;
            self.scale_y = 0;
        }

        /// Sets the drawn size, in pixels, for the font's full line height.
        ///
        /// Scaling lives here rather than being threaded through each call, so
        /// there is exactly one definition of "the current size".
        pub fn setSize(self: *Self, pixel_height: f32) void {
            self.b.setSize(pixel_height);

            const vm = self.b.verticalMetrics();
            const line_height: f32 = @floatFromInt(vm.ascent - vm.descent + vm.line_gap);
            if (line_height == 0) {
                self.scale_x = 0;
                self.scale_y = 0;
                return;
            }

            // Horizontal scale tracks the vertical one so glyphs keep their
            // designed proportions instead of being stretched.
            self.scale_y = pixel_height / line_height;
            self.scale_x = self.scale_y;
        }

        pub fn scale(self: *const Self) f32 {
            return self.scale_x;
        }

        /// Maps a codepoint to a glyph index, or `0` (`.notdef`) when this font
        /// has no glyph for it.
        ///
        /// Index 0 covers both "codepoint absent from cmap" and "cmap entry
        /// explicitly points at glyph 0". Either way the glyph is unusable, so
        /// it doubles as the signal to try the next font in a chain.
        pub fn glyphIndexForCodepoint(self: *const Self, codepoint: u21) u32 {
            return self.b.glyphIndexForCodepoint(codepoint);
        }

        /// Whether this font can render `codepoint` itself.
        ///
        /// Use this to decide whether to walk a fallback chain, rather than
        /// comparing against `.notdef` at each call site.
        pub fn hasCodepoint(self: *const Self, codepoint: u21) bool {
            return !backend.isNotdef(self.b.glyphIndexForCodepoint(codepoint));
        }

        /// Advance width for `glyph`, in pixels.
        ///
        /// Scaled here, from the backend's unscaled font units. A terminal must
        /// use the *primary* font's cell width for every glyph, including ones
        /// borrowed from a fallback, or the cursor drifts off the column grid.
        pub fn advanceWidth(self: *const Self, glyph: u32) f32 {
            return @as(f32, @floatFromInt(self.b.glyphMetrics(glyph).advance)) * self.scale_x;
        }

        /// Rasterizes `glyph`, appending 8-bit coverage pixels to `pixels`.
        pub fn glyphBitmap(
            self: *const Self,
            allocator: Allocator,
            pixels: *std.ArrayList(u8),
            glyph: u32,
        ) !backend.Bitmap {
            if (self.scale_x == 0) return backend.empty_bitmap;
            return self.b.glyphBitmap(allocator, pixels, glyph);
        }

        /// Terminal cell geometry derived from this face's own metrics.
        ///
        /// Only meaningful for the primary face, since it defines the grid.
        pub fn cellMetrics(self: *const Self) CellMetrics {
            const vm = self.b.verticalMetrics();

            const advance_px = @ceil(advanceWidthRaw(self.b, &self.scale_x));
            const line_height_px = @ceil(
                (@as(f32, @floatFromInt(vm.ascent - vm.descent)) +
                    @as(f32, @floatFromInt(vm.line_gap))) * self.scale_y,
            );
            const baseline_px = @ceil(@as(f32, @floatFromInt(vm.ascent)) * self.scale_y);

            return .{
                .cell_width = @intFromFloat(@max(1, advance_px)),
                .cell_height = @intFromFloat(@max(1, line_height_px)),
                .baseline = @intFromFloat(@max(1, baseline_px)),
            };
        }
    };
}

/// Unscaled advance of a codepoint known to exist, in pixels.
///
/// Probes '0', 'M', 'H' because a font missing its digits would otherwise
/// report a zero-width cell.
fn advanceWidthRaw(b: anytype, scale: *const f32) f32 {
    inline for (.{ '0', 'M', 'H' }) |codepoint| {
        const glyph = b.glyphIndexForCodepoint(codepoint);
        if (!backend.isNotdef(glyph))
            return @as(f32, @floatFromInt(b.glyphMetrics(glyph).advance)) * scale.*;
    }
    return 0;
}

comptime {
    std.testing.refAllDecls(@This());
}

const Interface = @This();

pub const VTable = struct {
    init: *const fn (alloc: std.mem.Allocator) *anyopaque,
    deinit: *const fn (self: *anyopaque) void,

    resize_surface: *const fn (self: *anyopaque, width: u32, hieght: u32) void,
    set_viewport: *const fn (self: *anyopaque, x: u32, y: u32, width: u32, hieght: u32) void,

    /// Each glyph’s bitmap is stored sequentially in `bitmap_pool`, and its size
    /// is determined by the corresponding entry in `dimensions`.
    cache_glyphs: *const fn (self: *anyopaque, dimensions: []const GlyphBitmap, bitmap_pool: []const u8) anyerror!void,

    // clear_glyph_cache: *const fn (self: *anyopaque) anyerror!void,
};

ptr: *anyopaque,
vtable: VTable,

const std = @import("std");
const TrueType = @import("TrueType");

const GlyphBitmap = TrueType.GlyphBitmap;

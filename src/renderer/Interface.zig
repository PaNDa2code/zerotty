const Interface = @This();

pub const VTable = struct {
    const Context = *anyopaque;

    const InitError = error{};
    const CacheGlyphsError = error{};
    const PushBatchError = error{};
    const ReserveBatchError = error{};
    const CommitBatchError = error{};
    const DrawGlyphsError = error{};

    init: *const fn (alloc: std.mem.Allocator) InitError!*Context,
    deinit: *const fn (self: *Context) void,

    resize_surface: *const fn (self: *Context, width: u32, height: u32) void,
    set_viewport: *const fn (self: *Context, x: u32, y: u32, width: u32, height: u32) void,

    /// copies glyphs bitmaps to GPU cache texture.
    /// each glyph’s bitmap is stored sequentially in `bitmap_pool`, and its size
    /// is determined by the corresponding entry in `dimensions`.
    cache_glyphs: *const fn (self: *Context, dimensions: []const GlyphBitmap, bitmap_pool: []const u8) CacheGlyphsError!void,

    /// Clears the texture atlas in case of font resizeing or else.
    reset_glyph_cache: *const fn (self: *Context) void,

    /// alternative for `reserve_batch` then `commit_batch`
    push_batch: *const fn (self: *Context, []const Instance) PushBatchError!void,

    /// reserve (or map) a CPU visable memory to write the instance data to.
    /// returned memory can be heap-allocated or GPU visable memory.
    reserve_batch: *const fn (self: *Context, count: usize) ReserveBatchError![]Instance,

    /// submit the reserved memory previously returned by `reserve_batch`
    commit_batch: *const fn (self: *Context, count: usize) CommitBatchError!void,

    /// draw current batch to the current frame
    draw: *const fn (self: *Context) DrawGlyphsError!void,

    /// clears the aquired image background
    clear: *const fn (self: *Context, color: RGBA) void,

    /// waits for the current frame resources to be released
    begin_frame: *const fn (self: *Context) void,

    /// binding resources for the GPU to be ready for rendering
    end_frame: *const fn (self: *Context) void,

    /// presents the current frame
    present: *const fn (self: *Context) void,
};

inner: *anyopaque,
vtable: VTable,

const std = @import("std");
const color = @import("color");
const win = @import("window");
const TrueType = @import("TrueType");

const RGBA = color.RGBA;

const GlyphBitmap = TrueType.GlyphBitmap;

const Instance = @import("vertex.zig").Instance;

pub fn makeVTable(comptime Impl: type) VTable {
    return .{
        .init = Impl.init,
        .deinit = Impl.deinit,
        .resize_surface = Impl.resizeSurface,
        .set_viewport = Impl.setViewport,
        .cache_glyphs = Impl.cacheGlyphs,
        .reset_glyph_cache = Impl.resetGlyphCache,
        .push_batch = Impl.pushBatch,
        .reserve_batch = Impl.reserveBatch,
        .commit_batch = Impl.commitBatch,
        .draw = Impl.draw,
        .clear = Impl.clear,
        .begin_frame = Impl.beginFrame,
        .end_frame = Impl.endFrame,
        .present = Impl.present,
    };
}

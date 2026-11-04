const font = @import("zerotty").font;
const color = @import("zerotty").terminal.color;

pub const RendererSettings = struct {
    surface_height: u32,
    surface_width: u32,
    grid_rows: u32,
    grid_cols: u32,
    cell_width: u32,
    cell_height: u32,
    baseline: i32 = 0,
};

pub const Renderer = @import("vulkan/Renderer.zig");

pub const vertex = @import("vertex.zig");
pub const spirv = @import("spirv.zig");

pub const RowRange = struct { first: u32, count: u32 };

pub const Damage = union(enum) {
    none,
    full,
    rows: []const RowRange,
};

pub const GlyphUpload = struct {
    entries: []const font.GlyphAtlasEntry = &.{},
    bitmaps: []const u8 = &.{},
};

pub const Scene = struct {
    clear_color: color.RGBA,
    cell_metrics: font.CellMetrics,

    grid_size: struct { rows: u32, cols: u32 },

    instances: []const vertex.TextInstance,
    background: []const u8,

    damage: Damage,

    glyph_upload: GlyphUpload = .{},
};

pub const PresentResult = enum {
    ok,
    suboptimal,
    out_of_date,
};

comptime {
    @import("std").testing.refAllDecls(@This());
}

pub const Font = @This();

pub const Face = @import("Face.zig");

ttf: TrueType,
faces: []Face,

scale_x: f32,
scale_y: f32,

pub const CellMetrics = struct {
    cell_width: u8,
    cell_height: u8,
    baseline: u8,
};

/// Terminal cell size derived from the font's own metrics instead of a fixed
/// aspect ratio:
/// - `cell_width`:  monospace advance width (glyph '0', fallback 'M') scaled
/// - `cell_height`: full line height (ascent - descent + line_gap) scaled
/// - `baseline`:    scaled ascent (distance from cell top to baseline)
pub fn cellMetrics(self: *const Font) CellMetrics {
    const vm = self.ttf.verticalMetrics();

    const advance_px = @ceil(@as(f32, @floatFromInt(cellProbeAdvance(&self.ttf))) * self.scale_x);
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

fn cellProbeAdvance(tt: *const TrueType) i16 {
    inline for (.{ '0', 'M', 'H' }) |codepoint| {
        const glyph = tt.codepointGlyphIndex(codepoint);
        if (glyph != .notdef)
            return tt.glyphHMetrics(glyph).advance_width;
    }
    return 0;
}

pub fn init(
    ttf_buffer: []const u8,
    height: u8,
) !Font {
    const ttf = try TrueType.load(ttf_buffer);
    const scale_y = ttf.scaleForPixelHeight(@floatFromInt(height));

    return .{
        .ttf = ttf,
        .faces = &.{},
        .scale_x = scale_y,
        .scale_y = scale_y,
    };
}

pub fn deinit(self: *const Font) void {
    _ = self;
}

pub fn face(self: *const Font, style: Face.Style) Face {
    _ = style;
    return .{
        .font = self,
        .style = .{},
    };
}

const TrueType = @import("TrueType");

const CellProgram = @This();

pub const Cell = packed struct {
    packed_pos: u32,
    glyph_index: u32 = '█',
    style_index: u32,
};

pub const CellStyle = extern struct {
    fg_color: ColorRGBAf32,
    bg_color: ColorRGBAf32,
};

cells: []Cell,
rows: u32 = 0,
cols: u32 = 0,

pub const CellProgramOptions = struct {
    rows: usize = 0,
    cols: usize = 0,
};

pub fn create(allocator: Allocator, options: CellProgramOptions) !CellProgram {
    const cells = try allocator.alloc(Cell, options.rows * options.cols);

    return .{
        .cells = cells,
        .rows = @intCast(options.rows),
        .cols = @intCast(options.cols),
    };
}

pub fn free(self: *CellProgram, allocator: Allocator) void {
    allocator.free(self.cells);
}

pub fn data(self: *const CellProgram) []const Cell {
    return self.cells;
}

pub fn resize(self: *CellProgram, allocator: Allocator, options: CellProgramOptions) !void {
    _ = self; // autofix
    _ = allocator; // autofix
    _ = options; // autofix
}

pub fn set(
    self: *CellProgram,
    row: u32,
    col: u32,
    glyph_index: u32,
    style_index: u32,
) !void {
    self.cells[row * col + col] = .{
        .packed_pos = (col << 16) | row,
        .glyph_index = glyph_index,
        .style_index = style_index,
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ColorRGBAu8 = @import("renderer/common/color.zig").ColorRGBAu8;
const ColorRGBAf32 = @import("renderer/common/color.zig").ColorRGBAf32;
const math = @import("renderer/common/math.zig");
const Vec2 = math.Vec2;

const font = @import("font/root.zig");
const Atlas = font.Atlas;

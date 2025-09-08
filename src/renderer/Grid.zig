const CellProgram = @This();

pub const Cell = packed struct {
    row: u32, // location 1
    col: u32, // location 2
    char: u32, // location 3
    fg_color: ColorRGBAu8, // location 4
    bg_color: ColorRGBAu8, // location 5
    glyph_info: Atlas.GlyphInfo = undefined, // location 6, 7, 8
};

const test_cell = Cell;

map: std.AutoArrayHashMap(Vec2(u32), Cell),
rows: u32 = 0,
cols: u32 = 0,

pub const CellProgramOptions = struct {
    rows: usize = 0,
    cols: usize = 0,
};

pub fn create(allocator: Allocator, options: CellProgramOptions) !CellProgram {
    const map = std.AutoArrayHashMap(Vec2(u32), Cell).init(allocator);

    return .{
        .map = map,
        .rows = @intCast(options.rows),
        .cols = @intCast(options.cols),
    };
}

pub fn free(self: *CellProgram) void {
    self.map.deinit();
}

pub fn data(self: *CellProgram) []Cell {
    return self.map.values();
}

pub fn resize(self: *CellProgram, allocator: Allocator, options: CellProgramOptions) !void {
    _ = self; // autofix
    _ = allocator; // autofix
    _ = options; // autofix
}

pub fn set(self: *CellProgram, cell: Cell) !void {
    try self.map.put(.{ .x = cell.row, .y = cell.col }, cell);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const ColorRGBAu8 = common.ColorRGBAu8;
const math = @import("math.zig");
const Vec2 = math.Vec2;

const font = @import("../font/root.zig");
const Atlas = font.Atlas;

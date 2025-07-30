const CellProgram = @This();

pub const Cell = packed struct {
    row: u32, // location 1
    col: u32, // location 2
    char: u32, // location 3
    fg_color: ColorRGBA, // location 4
    bg_color: ColorRGBA, // location 5
    glyph_info: Atlas.GlyphInfo = undefined, // location 6, 7, 8
};

const test_cell = Cell;

map: std.AutoArrayHashMap(Vec2(u32), Cell),
rows: u32,
columns: u32,

pub const CellProgramOptions = struct {
    cell_height: usize,
    cell_width: usize,
    screen_height: usize,
    screen_width: usize,
};

pub fn create(allocator: Allocator, options: CellProgramOptions) !CellProgram {
    const rows = options.screen_height / options.cell_height;
    const columns = options.screen_width / options.cell_width;

    const map = std.AutoArrayHashMap(Vec2(u32), Cell).init(allocator);

    return .{
        .map = map,
        .rows = @intCast(rows),
        .columns = @intCast(columns),
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
const ColorRGBA = common.ColorRGBA;
const math = @import("math.zig");
const Vec2 = math.Vec2;

const font = @import("../font/root.zig");
const Atlas = font.Atlas;

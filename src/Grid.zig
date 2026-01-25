pub const CellProgram = @This();

pub const Cell = packed struct {
    packed_pos: u32,
    glyph_index: u32,
    style_index: u32,
};

pub const CellStyle = extern struct {
    fg_color: ColorRGBAf32,
    bg_color: ColorRGBAf32,
};

map: std.AutoArrayHashMap(u32, Cell),
rows: u32 = 0,
cols: u32 = 0,

pub const CellProgramOptions = struct {
    rows: usize = 0,
    cols: usize = 0,
};

pub fn create(allocator: Allocator, options: CellProgramOptions) !CellProgram {
    const map = std.AutoArrayHashMap(u32, Cell).init(allocator);

    return .{
        .map = map,
        .rows = @intCast(options.rows),
        .cols = @intCast(options.cols),
    };
}

pub fn free(self: *CellProgram, allocator: Allocator) void {
    _ = allocator;
    self.map.deinit();
}

pub fn data(self: *const CellProgram) []const Cell {
    return self.map.values();
}

pub fn resize(self: *CellProgram, allocator: Allocator, options: CellProgramOptions) !void {
    _ = self; // autofix
    _ = allocator; // autofix
    _ = options; // autofix
}

pub fn set(self: *CellProgram, cell: Cell) !void {
    try self.map.put(cell.packed_pos, cell);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("color");
const ColorRGBAu8 = color.RGBA;
const ColorRGBAf32 = color.RGBA;
const math = @import("math");
const Vec2 = math.Vec2;

const font = @import("font");
const Atlas = font.Atlas;

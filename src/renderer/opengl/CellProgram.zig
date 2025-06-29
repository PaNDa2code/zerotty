const CellProgram = @This();

pub const Cell = packed struct {
    row: u32, // location 1
    col: u32, // location 2
    char: u32, // location 3
    fg_color: ColorRGBA, // location 4
    bg_color: ColorRGBA, // location 5
};

const test_cell = Cell;

data: []Cell,
rows: u32,
columns: u32,

pub fn create(allocator: Allocator, screen_height: usize, screen_width: usize, cell_size: usize) !CellProgram {
    const rows = screen_height / cell_size;
    const columns = screen_width / cell_size;

    const data = try allocator.alloc(Cell, rows * columns);

    @memset(data, .{
        .row = 0,
        .col = 0,
        .char = 'a',
        .fg_color = .White,
        .bg_color = .Gray,
    });

    for (data, 0..) |*cell, i| {
        cell.char = @intCast('a' + (i % 26));
        cell.row = @intCast(i / columns);
        cell.col = @intCast(i % columns);
    }

    return .{
        .data = data,
        .rows = @intCast(rows),
        .columns = @intCast(columns),
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("../common.zig");
const ColorRGBA = common.ColorRGBA;
